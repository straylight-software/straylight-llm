{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Multi-core evring-wai with round-robin connection dispatch.
--
-- Architecture:
--   - Single acceptor thread accepts all connections
--   - Round-robin dispatch to N worker threads
--   - Each worker has its own io_uring ring
--   - Workers poll a lock-free queue for new connections
--
-- This avoids SO_REUSEPORT hash distribution issues with localhost.
module Evring.Wai.MultiCoreRR
  ( runServerMultiCoreRR,
    ServerSettings (..),
    defaultServerSettings,
  )
where

import Control.Concurrent (forkOn, getNumCapabilities)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forM_, forever, when)
import Data.Bits ((.&.))
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.Int (Int64)
import Data.Primitive (MutablePrimArray, newPinnedPrimArray, readPrimArray, writePrimArray)
import Data.Primitive.Array (MutableArray, newArray, readArray, writeArray)
import Evring.Wai.Conn (ConnContext, newConnContext, startConnection)
import Evring.Wai.Loop
  ( CompletionResult(..), Cont(..), Loop(..)
  , batchSize, freeSlot, withLoop
  )
import Foreign.C.Types (CInt (..))
import GHC.Conc (setNumCapabilities)
import GHC.Exts (RealWorld)
import Network.Socket
import Network.Wai (Application)
import System.Posix.Types (Fd (..))

import System.IoUring.URing qualified as URing

-- | Server settings
data ServerSettings = ServerSettings
  { serverPort :: !Int,
    serverBacklog :: !Int,
    serverRingSize :: !Int,
    serverMaxConns :: !Int,
    serverCores :: !(Maybe Int)
  }

defaultServerSettings :: ServerSettings
defaultServerSettings =
  ServerSettings
    { serverPort = 8080,
      serverBacklog = 8192,
      serverRingSize = 4096,
      serverMaxConns = 4096,
      serverCores = Nothing
    }

-- ════════════════════════════════════════════════════════════════════════════
-- LOCK-FREE SPSC QUEUE (Single Producer Single Consumer)
-- Each worker has its own queue, acceptor is the only producer
-- ════════════════════════════════════════════════════════════════════════════

data ConnQueue = ConnQueue
  { cqFds :: !(MutablePrimArray RealWorld CInt)  -- ring buffer of fds
  , cqAddrs :: !(MutableArray RealWorld SockAddr) -- corresponding addresses
  , cqHead :: !(IORef Int)  -- producer writes here (acceptor)
  , cqTail :: !(IORef Int)  -- consumer reads here (worker)
  , cqMask :: !Int          -- capacity - 1 (power of 2)
  }

newConnQueue :: Int -> IO ConnQueue
newConnQueue size = do
  -- Round up to power of 2
  let capacity = nextPow2 size
      mask = capacity - 1
  fds <- newPinnedPrimArray capacity
  addrs <- newArray capacity (SockAddrInet 0 0)
  headRef <- newIORef 0
  tailRef <- newIORef 0
  pure ConnQueue
    { cqFds = fds
    , cqAddrs = addrs
    , cqHead = headRef
    , cqTail = tailRef
    , cqMask = mask
    }
  where
    nextPow2 :: Int -> Int
    nextPow2 n = go 1
      where
        go !x
          | x >= n = x
          | otherwise = go (x * 2)

-- | Push a connection to the queue (called by acceptor)
{-# INLINE pushConn #-}
pushConn :: ConnQueue -> CInt -> SockAddr -> IO Bool
pushConn ConnQueue{..} fd addr = do
  h <- readIORef cqHead
  t <- readIORef cqTail
  let sz = h - t
  if sz > cqMask
    then pure False  -- queue full
    else do
      let idx = h .&. cqMask
      writePrimArray cqFds idx fd
      writeArray cqAddrs idx addr
      writeIORef cqHead (h + 1)
      pure True

-- | Pop a connection from the queue (called by worker)
{-# INLINE popConn #-}
popConn :: ConnQueue -> IO (Maybe (CInt, SockAddr))
popConn ConnQueue{..} = do
  h <- readIORef cqHead
  t <- readIORef cqTail
  if h == t
    then pure Nothing  -- queue empty
    else do
      let idx = t .&. cqMask
      fd <- readPrimArray cqFds idx
      addr <- readArray cqAddrs idx
      writeIORef cqTail (t + 1)
      pure $ Just (fd, addr)

-- ════════════════════════════════════════════════════════════════════════════
-- MULTI-CORE SERVER
-- ════════════════════════════════════════════════════════════════════════════

-- | Run server with round-robin connection dispatch
runServerMultiCoreRR :: ServerSettings -> Application -> IO ()
runServerMultiCoreRR settings@ServerSettings {..} app = do
  numCores <- case serverCores of
    Just n -> setNumCapabilities n >> pure n
    Nothing -> getNumCapabilities

  putStrLn $ "evring-wai (round-robin): Starting on port " ++ show serverPort
  putStrLn $ "  Cores: " ++ show numCores
  putStrLn $ "  Ring size: " ++ show serverRingSize
  putStrLn ""

  -- Create one queue per worker
  queues <- mapM (\_ -> newConnQueue 4096) [0 .. numCores - 1]

  -- Create single listen socket
  listenSock <- createListenSocket settings

  -- Start workers (they poll their queues)
  workerDones <- mapM (\_ -> newEmptyMVar) [0 .. numCores - 1]
  forM_ (zip3 [0 ..] queues workerDones) $ \(coreId, queue, done) -> do
    _ <- forkOn coreId $ do
      runWorkerRR settings app queue
      putMVar done ()
    pure ()

  -- Run acceptor on core 0 (or dedicated core)
  _ <- forkOn 0 $ runAcceptor listenSock queues numCores

  -- Wait for workers
  mapM_ takeMVar workerDones
  close listenSock

-- | Create listening socket (single, no SO_REUSEPORT)
createListenSocket :: ServerSettings -> IO Socket
createListenSocket ServerSettings {..} = do
  sock <- socket AF_INET Stream 0
  setSocketOption sock ReuseAddr 1
  setSocketOption sock NoDelay 1
  bind sock (SockAddrInet (fromIntegral serverPort) 0)
  listen sock serverBacklog
  pure sock

-- | Acceptor thread - accepts and round-robins to workers
runAcceptor :: Socket -> [ConnQueue] -> Int -> IO ()
runAcceptor sock queues numWorkers = do
  counter <- newIORef (0 :: Int)
  let queueArr = queues  -- could convert to array for O(1) indexing
  
  forever $ do
    (clientSock, clientAddr) <- accept sock
    fd <- withFdSocket clientSock pure
    
    -- Round-robin to next worker
    idx <- atomicModifyIORef' counter $ \n -> 
      let next = (n + 1) `mod` numWorkers in (next, n)
    
    let queue = queueArr !! idx
    success <- pushConn queue fd clientAddr
    
    -- If queue full, close connection (backpressure)
    when (not success) $ close clientSock

-- | Worker thread - polls queue and handles connections
runWorkerRR :: ServerSettings -> Application -> ConnQueue -> IO ()
runWorkerRR ServerSettings {..} app queue = do
  ctx <- newConnContext serverMaxConns

  withLoop serverRingSize $ \loop -> do
    runLoopWithPolling loop queue ctx app

-- | Modified loop that polls the queue between batches
runLoopWithPolling :: Loop -> ConnQueue -> ConnContext -> Application -> IO ()
runLoopWithPolling loop@Loop{..} queue ctx app = go
  where
    go = do
      running <- readIORef loopRunning
      if not running
        then pure ()
        else do
          -- Poll queue for new connections
          hadNewConns <- drainQueue
          
          -- If we have pending IO or got new connections, do a tight non-blocking loop
          -- Otherwise wait with a small timeout to avoid busy-spinning
          count <- if hadNewConns
            then URing.submitWaitTimeoutDrain loopRing loopBatchUserData loopBatchResults batchSize 0
            else URing.submitWaitTimeoutDrain loopRing loopBatchUserData loopBatchResults batchSize 10
          
          -- Dispatch completions (if any)
          dispatchBatch loop count 0
          
          go
    
    drainQueue = go' False
      where
        go' !hadAny = do
          mConn <- popConn queue
          case mConn of
            Nothing -> pure hadAny
            Just (fd, addr) -> do
              startConnection ctx loop (Fd fd) addr app
              go' True

-- | Dispatch batch of completions
{-# INLINE dispatchBatch #-}
dispatchBatch :: Loop -> Int -> Int -> IO ()
dispatchBatch loop@Loop{..} !count !i
  | i >= count = pure ()
  | otherwise = do
      userData <- readPrimArray loopBatchUserData i
      res <- readPrimArray loopBatchResults i
      dispatchRaw loop (fromIntegral userData) res
      dispatchBatch loop count (i + 1)

{-# INLINE dispatchRaw #-}
dispatchRaw :: Loop -> Int -> Int64 -> IO ()
dispatchRaw loop@Loop{..} slot res = do
  mCont <- readArray loopConts slot
  case mCont of
    Nothing -> pure ()
    Just (Cont k) -> do
      let !result = if res < 0 
                    then Failure (fromIntegral (-res))
                    else Success res
      mNext <- k result
      case mNext of
        Nothing -> freeSlot loop slot
        Just next -> writeArray loopConts slot (Just next)
