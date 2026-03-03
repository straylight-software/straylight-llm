-- Manual FFI bindings for io_uring (no hsc)
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module System.IoUring.URing
  ( URing (URing, uRingPtr),
    URingParams (..),
    initURing,
    closeURing,
    cleanupURing,
    validURing,
    submitIO,
    awaitIO,
    peekIO,
    -- * Batch operations (for high-throughput polling loops)
    submitWaitTimeoutDrain,
    IOCompletion (..),
    IOResult (..),
    IOOpId (..),
  )
where

-- Control.Monad not needed
import Data.Int (Int32, Int64)
import Data.Word (Word32, Word64)
import Data.Primitive (MutablePrimArray, writePrimArray)
import Foreign (Ptr, alloca, callocBytes, free, peek, peekByteOff)
import GHC.Exts (RealWorld)
import System.IoUring.Internal.FFI
  ( c_hs_uring_cqe_seen,
    c_hs_uring_peek_cqe,
    c_hs_uring_wait_cqe,
    c_hs_uring_wait_cqe_timeout,
    c_io_uring_queue_exit,
    c_io_uring_queue_init,
    c_io_uring_submit,
  )

-- ============================================================================
-- TYPES
-- ============================================================================

newtype IOResult = IOResult Int64
  deriving stock (Show)

newtype IOOpId = IOOpId Word64
  deriving stock (Show, Eq)

data IOCompletion = IOCompletion
  { completionId :: !IOOpId,
    completionRes :: !IOResult
  }
  deriving stock (Show)

data URingParams = URingParams
  { uringSqEntries :: !Word32,
    uringCqEntries :: !Word32,
    uringFlags :: !Word32
  }
  deriving stock (Show)

-- ============================================================================
-- FFI WRAPPERS
-- ============================================================================

data URing = URing
  { uRingPtr :: !(Ptr ())
  }

-- io_uring setup flags for single-threaded high-performance use
-- These are available in Linux 6.0+

-- Use default flags (no special setup) for maximum compatibility and stability
-- SINGLE_ISSUER and COOP_TASKRUN can cause issues with certain workloads

initURing :: Int -> Int -> Int -> IO URing
initURing _capNo sqEntries _cqEntries = do
  ptr <- callocBytes 4096 -- Conservative estimate for io_uring struct (increased for safety)
  ret <- c_io_uring_queue_init (fromIntegral sqEntries) ptr 0
  if ret < 0
    then do
      free ptr
      ioError $ userError "io_uring_queue_init failed"
    else return $ URing ptr

closeURing :: URing -> IO ()
closeURing (URing ptr) = do
  c_io_uring_queue_exit ptr
  free ptr

cleanupURing :: URing -> IO ()
cleanupURing = closeURing

validURing :: URing -> IO Bool
validURing _ = return True

-- ============================================================================
-- SUBMISSION
-- ============================================================================

submitIO :: URing -> IO ()
submitIO (URing ptr) = do
  ret <- c_io_uring_submit ptr
  if ret < 0
    then ioError $ userError $ "io_uring_submit failed: " ++ show ret
    else return ()

-- ============================================================================
-- COMPLETIONS
-- ============================================================================

awaitIO :: URing -> IO IOCompletion
awaitIO (URing ringPtr) = alloca $ \cqePtrPtr -> do
  res <- c_hs_uring_wait_cqe ringPtr cqePtrPtr
  if res < 0
    then ioError $ userError $ "io_uring_wait_cqe failed: " ++ show res
    else do
      cqePtr <- peek cqePtrPtr
      userData <- peekByteOff cqePtr 0 :: IO Word64
      res32 <- peekByteOff cqePtr 8 :: IO Int32

      c_hs_uring_cqe_seen ringPtr cqePtr

      return $ IOCompletion (IOOpId userData) (IOResult (fromIntegral res32))

peekIO :: URing -> IO (Maybe IOCompletion)
peekIO (URing ringPtr) = alloca $ \cqePtrPtr -> do
  res <- c_hs_uring_peek_cqe ringPtr cqePtrPtr
  if res == 0 -- 0 means success (found cqe)
    then do
      cqePtr <- peek cqePtrPtr
      userData <- peekByteOff cqePtr 0 :: IO Word64
      res32 <- peekByteOff cqePtr 8 :: IO Int32

      c_hs_uring_cqe_seen ringPtr cqePtr

      return $ Just $ IOCompletion (IOOpId userData) (IOResult (fromIntegral res32))
    else return Nothing

-- ============================================================================
-- BATCH OPERATIONS
-- ============================================================================

-- | Submit pending SQEs, wait for completions with timeout, drain into arrays.
-- 
-- This is optimized for high-throughput polling loops:
-- 1. Submits any pending SQEs
-- 2. Waits for at least one completion (or timeout in milliseconds, 0 = non-blocking)
-- 3. Drains up to maxCount completions into the provided arrays
-- 4. Returns the count of completions drained
--
-- The arrays must have at least maxCount capacity.
submitWaitTimeoutDrain 
  :: URing 
  -> MutablePrimArray RealWorld Int64  -- ^ Output: user data (slot IDs)
  -> MutablePrimArray RealWorld Int64  -- ^ Output: results
  -> Int                               -- ^ Maximum completions to drain
  -> Int                               -- ^ Timeout in milliseconds (0 = non-blocking)
  -> IO Int                            -- ^ Number of completions drained
submitWaitTimeoutDrain (URing ringPtr) userDataArr resultsArr maxCount timeoutMs = do
  -- Submit pending SQEs first
  _ <- c_io_uring_submit ringPtr
  
  -- Wait for first completion (with timeout)
  alloca $ \cqePtrPtr -> do
    res <- if timeoutMs <= 0
           then c_hs_uring_peek_cqe ringPtr cqePtrPtr
           else c_hs_uring_wait_cqe_timeout ringPtr cqePtrPtr (fromIntegral timeoutMs)
    
    if res /= 0
      then return 0  -- No completions available (timeout or empty)
      else do
        -- Got first completion, process it
        cqePtr <- peek cqePtrPtr
        userData <- peekByteOff cqePtr 0 :: IO Word64
        res32 <- peekByteOff cqePtr 8 :: IO Int32
        c_hs_uring_cqe_seen ringPtr cqePtr
        
        writePrimArray userDataArr 0 (fromIntegral userData)
        writePrimArray resultsArr 0 (fromIntegral res32)
        
        -- Drain remaining completions (non-blocking)
        drainMore 1
  where
    drainMore !count
      | count >= maxCount = return count
      | otherwise = alloca $ \cqePtrPtr -> do
          res <- c_hs_uring_peek_cqe ringPtr cqePtrPtr
          if res /= 0
            then return count  -- No more completions
            else do
              cqePtr <- peek cqePtrPtr
              userData <- peekByteOff cqePtr 0 :: IO Word64
              res32 <- peekByteOff cqePtr 8 :: IO Int32
              c_hs_uring_cqe_seen ringPtr cqePtr
              
              writePrimArray userDataArr count (fromIntegral userData)
              writePrimArray resultsArr count (fromIntegral res32)
              
              drainMore (count + 1)
