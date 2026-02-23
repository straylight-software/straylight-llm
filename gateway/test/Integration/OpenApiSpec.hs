-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                               // straylight-llm // integration // openapi spec
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Case was thoroughly fried. His nervous system had been 
--      permanently scarred by a wartime Russian virus."
--
--                                                              — Neuromancer
--
-- OpenAPI spec validation tests.
-- Validates that the OpenAPI specification is well-formed and complete.
--
-- For full conformance testing with haskemathesis, run:
--   cabal test --test-option=--pattern="OpenAPI Conformance"
-- with haskemathesis available via cabal.project.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE OverloadedStrings #-}

module Integration.OpenApiSpec
    ( tests
    ) where

import qualified Data.ByteString as BS
import qualified Data.HashMap.Strict.InsOrd as IOHM
import Data.OpenApi (OpenApi (..))
import qualified Data.OpenApi as OA
import Data.Text (Text)
import qualified Data.Text as T
import Data.Yaml (decodeEither')
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, assertFailure)


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // spec loading
-- ════════════════════════════════════════════════════════════════════════════

-- | Path to the OpenAPI specification
specPath :: FilePath
specPath = "openapi.yaml"

-- | Load and parse the OpenAPI spec
loadSpec :: IO (Either Text OpenApi)
loadSpec = do
    contents <- BS.readFile specPath
    pure $ case decodeEither' contents of
        Left err -> Left $ T.pack $ show err
        Right spec -> Right spec


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // test trees
-- ════════════════════════════════════════════════════════════════════════════

-- | All OpenAPI spec validation tests
tests :: TestTree
tests = testGroup "OpenAPI Spec"
    [ specLoadTest
    , specStructureTests
    , endpointTests
    , schemaTests
    ]

-- | Test that the spec loads successfully
specLoadTest :: TestTree
specLoadTest = testCase "spec loads as valid OpenAPI 3.x" $ do
    result <- loadSpec
    case result of
        Left err -> assertFailure $ "Failed to parse spec: " ++ T.unpack err
        Right _spec -> pure ()

-- | Test spec structure
specStructureTests :: TestTree
specStructureTests = testGroup "Structure"
    [ testCase "has info section" $ do
        result <- loadSpec
        case result of
            Left err -> assertFailure $ T.unpack err
            Right spec -> do
                let info = OA._openApiInfo spec
                assertBool "has title" (not $ T.null $ OA._infoTitle info)
                assertBool "has version" (not $ T.null $ OA._infoVersion info)

    , testCase "has paths section" $ do
        result <- loadSpec
        case result of
            Left err -> assertFailure $ T.unpack err
            Right spec -> do
                let paths = OA._openApiPaths spec
                assertBool "has at least one path" (not $ IOHM.null paths)

    , testCase "has components section" $ do
        result <- loadSpec
        case result of
            Left err -> assertFailure $ T.unpack err
            Right spec -> do
                -- Components is not Maybe in openapi3 - check schemas exist
                let components = OA._openApiComponents spec
                    schemas = OA._componentsSchemas components
                assertBool "has schemas" (not $ IOHM.null schemas)
    ]

-- | Test required endpoints exist
endpointTests :: TestTree
endpointTests = testGroup "Endpoints"
    [ testCase "has /v1/chat/completions" $ assertHasPath "/v1/chat/completions"
    , testCase "has /v1/completions" $ assertHasPath "/v1/completions"
    , testCase "has /v1/embeddings" $ assertHasPath "/v1/embeddings"
    , testCase "has /v1/models" $ assertHasPath "/v1/models"
    , testCase "has /v1/proof/{requestId}" $ assertHasPath "/v1/proof/{requestId}"
    , testCase "has /health" $ assertHasPath "/health"
    ]

-- | Test required schemas exist
schemaTests :: TestTree
schemaTests = testGroup "Schemas"
    [ testCase "has ChatRequest schema" $ assertHasSchema "ChatRequest"
    , testCase "has ChatResponse schema" $ assertHasSchema "ChatResponse"
    , testCase "has Message schema" $ assertHasSchema "Message"
    , testCase "has EmbeddingRequest schema" $ assertHasSchema "EmbeddingRequest"
    , testCase "has EmbeddingResponse schema" $ assertHasSchema "EmbeddingResponse"
    , testCase "has DischargeProof schema" $ assertHasSchema "DischargeProof"
    , testCase "has Coeffect schema" $ assertHasSchema "Coeffect"
    , testCase "has ApiError schema" $ assertHasSchema "ApiError"
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                              // helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Assert a path exists in the spec
-- n.b. openapi3 uses FilePath (String) for path keys
assertHasPath :: String -> IO ()
assertHasPath path = do
    result <- loadSpec
    case result of
        Left err -> assertFailure $ T.unpack err
        Right spec -> do
            let paths = OA._openApiPaths spec
                pathExists = IOHM.member path paths
            assertBool ("missing path: " ++ path) pathExists

-- | Assert a schema exists in the components
assertHasSchema :: Text -> IO ()
assertHasSchema schemaName = do
    result <- loadSpec
    case result of
        Left err -> assertFailure $ T.unpack err
        Right spec -> do
            let components = OA._openApiComponents spec
                schemas = OA._componentsSchemas components
                schemaExists = IOHM.member schemaName schemas
            assertBool ("missing schema: " ++ T.unpack schemaName) schemaExists
