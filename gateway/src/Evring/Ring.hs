{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // evring/ring
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace, hope fading nightly."
--
--                                                              — Neuromancer
--
-- Ring runner: connects pure state machines to actual I/O.
--
-- This is the only module that performs actual I/O. The machine abstraction
-- remains pure, enabling deterministic replay testing.
--
-- The runner implements the event loop:
--
-- 1. Get initial state from machine
-- 2. Step with empty event to get initial operations
-- 3. Submit operations to ring
-- 4. Wait for completions
-- 5. Step machine with completion event
-- 6. Repeat until done
--
-- For the gateway, we use HTTP client instead of io_uring directly,
-- but the abstraction remains the same.
--
-- Imported from: libevring/hs/Evring/Ring.hs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Evring.Ring
  ( -- * Running machines
    run
  , runTraced
  , runGenerate
  , runGenerateTraced
    -- * Ring configuration
  , RingConfig(..)
  , defaultRingConfig
    -- * Custom runners
  , runWith
  , Runner(..)
  ) where

import Data.IORef (IORef, newIORef, readIORef, modifyIORef')

import Evring.Event (Event, Operation, emptyEvent)
import Evring.Machine
  ( Machine(State, initial, step, done)
  , GeneratorMachine(wantsToSubmit, generate)
  , StepResult(StepResult)
  )
import Evring.Trace (Trace, emptyTrace, record)


-- ════════════════════════════════════════════════════════════════════════════
--                                                            // configuration
-- ════════════════════════════════════════════════════════════════════════════

-- | Ring configuration.
data RingConfig = RingConfig
  { ringEntries    :: !Int
    -- ^ Number of SQ entries (default 256)
  , ringCqEntries  :: !Int
    -- ^ Number of CQ entries (default 512)
  , ringBatchSize  :: !Int
    -- ^ Max operations to submit at once (default 64)
  } deriving (Eq, Show)

-- | Default ring configuration.
defaultRingConfig :: RingConfig
defaultRingConfig = RingConfig
  { ringEntries   = 256
  , ringCqEntries = 512
  , ringBatchSize = 64
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // runners
-- ════════════════════════════════════════════════════════════════════════════

-- | A runner encapsulates I/O operations.
--
-- This abstraction allows us to swap between real io_uring, HTTP clients,
-- or mock implementations for testing.
data Runner = Runner
  { runnerSubmit :: [Operation] -> IO ()
    -- ^ Submit operations to the ring
  , runnerAwait  :: IO Event
    -- ^ Wait for a completion event
  }

-- | Run a machine to completion.
--
-- This is the main entry point for executing a machine with actual I/O.
-- The machine's step function is called for each completion event until
-- the machine reports done.
--
-- Note: This uses a stub runner. For real I/O, use 'runWith'.
run :: forall m. Machine m => RingConfig -> m -> IO (State m)
run config machine = runWith config defaultRunner machine

-- | Run a machine to completion, recording a trace.
--
-- The trace can be used for replay testing.
runTraced :: forall m. Machine m => RingConfig -> m -> IO (State m, Trace)
runTraced config machine = runTracedWith config defaultRunner machine

-- | Run a generator machine to completion.
--
-- Generator machines can produce operations proactively via generate(),
-- not just in response to events. This is used for bulk operations.
runGenerate :: forall m. GeneratorMachine m => RingConfig -> m -> IO (State m)
runGenerate config machine = runGenerateWith config defaultRunner machine

-- | Run a generator machine to completion, recording a trace.
runGenerateTraced :: forall m. GeneratorMachine m => RingConfig -> m -> IO (State m, Trace)
runGenerateTraced config machine = runGenerateTracedWith config defaultRunner machine


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // custom runners
-- ════════════════════════════════════════════════════════════════════════════

-- | Run a machine with a custom runner.
runWith :: forall m. Machine m => RingConfig -> Runner -> m -> IO (State m)
runWith _config runner machine = do
    -- Initialize state
    let s0 = initial machine
    
    -- First step with empty event to trigger initial operations
    let StepResult s1 ops1 = step machine s0 emptyEvent
    
    -- Submit and process until done
    runLoop s1 ops1
  where
    runLoop :: State m -> [Operation] -> IO (State m)
    runLoop s ops = do
      -- Submit operations
      runnerSubmit runner ops
      
      -- Check if done
      if done machine s
        then return s
        else do
          -- Wait for completion and step
          event <- runnerAwait runner
          let StepResult s' ops' = step machine s event
          runLoop s' ops'

-- | Run a machine with a custom runner, recording a trace.
runTracedWith :: forall m. Machine m => RingConfig -> Runner -> m -> IO (State m, Trace)
runTracedWith _config runner machine = do
    traceRef <- newIORef emptyTrace
    
    let s0 = initial machine
    let StepResult s1 ops1 = step machine s0 emptyEvent
    
    finalState <- runLoop traceRef s1 ops1
    trace <- readIORef traceRef
    return (finalState, trace)
  where
    runLoop :: IORef Trace -> State m -> [Operation] -> IO (State m)
    runLoop traceRef s ops = do
      runnerSubmit runner ops
      
      if done machine s
        then return s
        else do
          event <- runnerAwait runner
          -- Record the event
          modifyIORef' traceRef (record event)
          let StepResult s' ops' = step machine s event
          runLoop traceRef s' ops'

-- | Run a generator machine with a custom runner.
runGenerateWith :: forall m. GeneratorMachine m => RingConfig -> Runner -> m -> IO (State m)
runGenerateWith config runner machine = do
    let s0 = initial machine
    runLoop s0
  where
    maxOps = ringBatchSize config
    
    runLoop :: State m -> IO (State m)
    runLoop s
      | done machine s = return s
      | wantsToSubmit machine s = do
          -- Generate operations
          let StepResult s' ops = generate machine s maxOps
          runnerSubmit runner ops
          
          -- Wait for completions and process
          if null ops
            then runLoop s'
            else do
              event <- runnerAwait runner
              let StepResult s'' _ = step machine s' event
              runLoop s''
      | otherwise = do
          -- No more to generate, wait for completions
          event <- runnerAwait runner
          let StepResult s' _ = step machine s event
          runLoop s'

-- | Run a generator machine with a custom runner, recording a trace.
runGenerateTracedWith :: forall m. GeneratorMachine m => RingConfig -> Runner -> m -> IO (State m, Trace)
runGenerateTracedWith config runner machine = do
    traceRef <- newIORef emptyTrace
    let s0 = initial machine
    finalState <- runLoop traceRef s0
    trace <- readIORef traceRef
    return (finalState, trace)
  where
    maxOps = ringBatchSize config
    
    runLoop :: IORef Trace -> State m -> IO (State m)
    runLoop traceRef s
      | done machine s = return s
      | wantsToSubmit machine s = do
          let StepResult s' ops = generate machine s maxOps
          runnerSubmit runner ops
          
          if null ops
            then runLoop traceRef s'
            else do
              event <- runnerAwait runner
              modifyIORef' traceRef (record event)
              let StepResult s'' _ = step machine s' event
              runLoop traceRef s''
      | otherwise = do
          event <- runnerAwait runner
          modifyIORef' traceRef (record event)
          let StepResult s' _ = step machine s event
          runLoop traceRef s'


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // default runner
-- ════════════════════════════════════════════════════════════════════════════

-- | Default runner (stub implementation).
--
-- This is a placeholder. In production, this would connect to:
-- - Real io_uring via System.IoUring
-- - HTTP client for network operations
-- - Other I/O backends
defaultRunner :: Runner
defaultRunner = Runner
  { runnerSubmit = \_ -> return ()  -- Stub
  , runnerAwait  = return emptyEvent  -- Stub
  }
