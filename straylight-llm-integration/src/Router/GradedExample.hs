{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TypeOperators #-}
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                             // Router (graded migration)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Sketch of Router.hs under the effect-monad graded system.
-- This is a MIGRATION GUIDE, not a drop-in replacement.
--
-- Key difference from current code:
--   Before: routeChat :: Router -> Text -> ChatRequest -> IO (Either ProviderError ChatResponse)
--           GatewayM a  (no type-level grade)
--
--   After:  routeChat :: Router -> Text -> ChatRequest -> IO (Either ProviderError ChatResponse)
--           GatewayM '[Net, Auth, Log, Crypto] a  (grade visible in types)
--
-- The IO wrapper stays — runGatewayM erases the grade. But internal
-- composition is now checked by GHC.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Router.GradedExample where

import Data.Text (Text)

-- effect-monad
import Effects.Do qualified as G
import Effects.Graded
import Effects.Grade

-- For reference only — these types are from the existing codebase
-- import Types (ChatRequest, ChatResponse)
-- import Provider.Types (Provider, ProviderError, ProviderResult)

-- Placeholder types for this example
data ChatRequest = ChatRequest { crModel :: Text }
data ChatResponse = ChatResponse { chatBody :: Text }
data Provider = Provider { provName :: Text }
data ProviderError = ProviderError Text
data Router = Router { routerProviders :: [Provider] }
data DischargeProof = DischargeProof


-- ════════════════════════════════════════════════════════════════════════════
-- BEFORE: current code (ungraded)
-- ════════════════════════════════════════════════════════════════════════════
--
-- routeChat :: Router -> Text -> ChatRequest -> IO (Either ProviderError ChatResponse)
-- routeChat router requestId req = do
--     ...
--     (result, _grade, prov, coeff) <- runGatewayM $ do
--         recordRequestId requestId      -- GatewayM ()
--         recordModel (crModel req)      -- GatewayM ()
--         result <- tryProviders ...     -- GatewayM (Either ProviderError ChatResponse)
--         ...
--         pure result
--     ...
--
-- The problem: GatewayM a tells the type checker nothing about what effects
-- this computation uses. A "pure" helper could secretly call liftGatewayIO
-- and make HTTP requests. The grading is purely aspirational.


-- ════════════════════════════════════════════════════════════════════════════
-- AFTER: graded version
-- ════════════════════════════════════════════════════════════════════════════

-- | Route a chat request through the provider fallback chain.
--
-- Grade: '[Net, Auth, Log, Crypto]
--   - Net:    HTTP calls to upstream providers
--   - Auth:   reading API keys from environment
--   - Log:    structured logging of routing decisions
--   - Crypto: signing the discharge proof
--
-- The grade is checked at compile time. If someone adds a filesystem
-- read inside this function without updating the signature, GHC rejects it.
routeChatGraded
  :: Router
  -> Text
  -> ChatRequest
  -> IO (Either ProviderError ChatResponse)
routeChatGraded router requestId req = do
  (result, grade, prov, coeff) <- runGatewayM (routeChatInner router requestId req)
  -- grade, prov, coeff available for discharge proof generation
  -- The type-level grade '[Net, Auth, Log, Crypto] has been erased —
  -- it served its purpose at compile time.
  pure result


-- | Inner graded computation. This is where the types do their work.
--
-- Note the QualifiedDo: G.do uses the graded bind from Control.Effect,
-- so GHC tracks the grade through each line. Regular do-blocks elsewhere
-- in this module use Prelude.(>>=) as normal.
routeChatInner
  :: Router
  -> Text
  -> ChatRequest
  -> GatewayM '[ 'Net, 'Auth, 'Log, 'Crypto ] (Either ProviderError ChatResponse)
routeChatInner router requestId req = G.do
  -- These are Pure — provenance bookkeeping doesn't require any effects.
  -- Grade so far: '[]
  recordRequestId requestId
  recordModel (crModel req)

  -- This introduces '[Net, Auth] into the grade.
  -- Grade so far: '[Net, Auth]  (= Union '[] '[Net, Auth])
  result <- tryProvidersGraded router req

  -- Signing introduces '[Crypto].
  -- Grade so far: '[Net, Auth, Crypto]
  _proof <- signResult result

  -- Logging introduces '[Log].
  -- Final grade: '[Net, Auth, Log, Crypto]  ✓ matches signature
  logRouteResult requestId result

  G.return result


-- | Try providers in the fallback chain.
-- Grade: '[Net, Auth] — network calls + credential usage.
tryProvidersGraded
  :: Router
  -> ChatRequest
  -> GatewayM '[ 'Net, 'Auth ] (Either ProviderError ChatResponse)
tryProvidersGraded router _req = G.do
  -- Read API key from config — this is Auth
  recordAuthUsage "openrouter" "chat"

  -- Make the HTTP call — this is Net
  recordHttpAccess "https://openrouter.ai/api/v1/chat" "POST" (Just 200)

  -- Record which provider we used — this is Pure (provenance bookkeeping)
  recordProvider "openrouter"

  G.return (Right (ChatResponse "hello from graded monad"))


-- | Sign a result to produce a discharge proof.
-- Grade: '[Crypto] — only cryptographic operations.
--
-- This is the key safety property: signResult CANNOT make network calls
-- or read config. If someone tried to add `liftNet someHttpCall` inside
-- this function, GHC would reject it because 'Net is not in '[Crypto].
signResult :: Either ProviderError ChatResponse -> GatewayM '[ 'Crypto ] DischargeProof
signResult _result = G.do
  -- liftNet (someHttpCall)  -- TYPE ERROR: 'Net not in '[Crypto]  ← this is the win
  liftCrypto (pure DischargeProof)


-- | Log the routing result.
-- Grade: '[Log] — only logging.
logRouteResult :: Text -> Either ProviderError ChatResponse -> GatewayM '[ 'Log ] ()
logRouteResult _requestId _result = G.do
  liftLog (putStrLn "route complete")


-- ════════════════════════════════════════════════════════════════════════════
-- HELPER: pure computations get '[] grade automatically
-- ════════════════════════════════════════════════════════════════════════════

-- | Select which provider to try first. Pure — just data manipulation.
-- Grade: '[] (Pure). Cannot perform any effects.
selectProvider :: Router -> ChatRequest -> GatewayM Pure Provider
selectProvider router _req =
  liftPure (head (routerProviders router))  -- TODO: real selection logic


-- ════════════════════════════════════════════════════════════════════════════
-- WHAT THE TYPES BUY YOU
-- ════════════════════════════════════════════════════════════════════════════
--
-- 1. SEPARATION OF CONCERNS
--    signResult :: ... -> GatewayM '[Crypto] DischargeProof
--    This function CANNOT make HTTP calls. Not by convention — by the type
--    system. If it needs network access, the signature must change, which
--    means the caller's signature changes too, all the way up the chain.
--    Code review becomes: "why did the grade of signResult change?"
--
-- 2. AUDIT TRAIL
--    The type signature IS the effect specification. For Boeing/Airbus
--    regulatory compliance, you can point to the type and say "this
--    function accesses only these resources, enforced by the compiler."
--
-- 3. DISCHARGE PROOF HONESTY
--    The discharge proof claims certain coeffects were used. The graded
--    monad ensures the claim matches reality — you can't produce a proof
--    that says "Pure" for a computation that made HTTP calls, because
--    the types wouldn't let you compose them.
--
-- 4. INCREMENTAL ADOPTION
--    liftIO' :: IO a -> GatewayM Full a
--    Any existing code can be wrapped in liftIO' to get Full grade.
--    Then you tighten the grades function by function, catching actual
--    effect violations as you go. The migration is mechanical.
--
-- 5. LEAN4 CORRESPONDENCE
--    Effects.Grade.GradeLabel corresponds 1:1 to Continuity.lean's
--    Coeffect inductive type. The type-level Union corresponds to the
--    lattice join. The Lean proofs about coeffect algebra now have
--    a Haskell witness — the Effect instance.
