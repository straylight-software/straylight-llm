{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                 // test // straylight // router
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Test.Straylight.Router (spec) where

import Data.IORef
import Test.Hspec

import Straylight.Config
import Straylight.Router


spec :: Spec
spec = do
  describe "RoutingDecision" $ do
    it "RouteToCgp equals itself" $
      RouteToCgp `shouldBe` RouteToCgp

    it "RouteToOpenRouter equals itself" $
      RouteToOpenRouter `shouldBe` RouteToOpenRouter

    it "NoBackendAvailable equals itself" $
      NoBackendAvailable `shouldBe` NoBackendAvailable

    it "different decisions are not equal" $
      RouteToCgp `shouldNotBe` RouteToOpenRouter

  describe "newRouterState" $ do
    it "creates state from default config" $ do
      rs <- newRouterState defaultConfig
      rsConfig rs `shouldBe` defaultConfig

    it "CGP is not configured with default config" $ do
      rs <- newRouterState defaultConfig
      rsCgp rs `shouldBe` Nothing

    it "OpenRouter is not configured with default config (no API key)" $ do
      rs <- newRouterState defaultConfig
      rsOpenRouter rs `shouldBe` Nothing

  describe "decideRoute" $ do
    it "returns NoBackendAvailable when nothing is configured" $ do
      rs <- newRouterState defaultConfig
      decision <- decideRoute rs
      decision `shouldBe` NoBackendAvailable

    it "routes to CGP when CGP is configured and healthy" $ do
      let cgpCfg = (cfgCgp defaultConfig) { cgpApiBase = "http://localhost:8000" }
          cfg = defaultConfig { cfgCgp = cgpCfg }
      rs <- newRouterState cfg
      -- Mark CGP as healthy
      writeIORef (rsCgpHealthy rs) True
      decision <- decideRoute rs
      decision `shouldBe` RouteToCgp

    it "routes to OpenRouter when CGP is unhealthy" $ do
      let cgpCfg = (cfgCgp defaultConfig) { cgpApiBase = "http://localhost:8000" }
          orCfg = (cfgOpenRouter defaultConfig) { orApiKey = Just "sk-test" }
          cfg = defaultConfig { cfgCgp = cgpCfg, cfgOpenRouter = orCfg }
      rs <- newRouterState cfg
      -- CGP unhealthy, OpenRouter healthy
      writeIORef (rsCgpHealthy rs) False
      writeIORef (rsOrHealthy rs) True
      decision <- decideRoute rs
      decision `shouldBe` RouteToOpenRouter

    it "prefers CGP over OpenRouter when both are healthy" $ do
      let cgpCfg = (cfgCgp defaultConfig) { cgpApiBase = "http://localhost:8000" }
          orCfg = (cfgOpenRouter defaultConfig) { orApiKey = Just "sk-test" }
          cfg = defaultConfig { cfgCgp = cgpCfg, cfgOpenRouter = orCfg }
      rs <- newRouterState cfg
      -- Both healthy
      writeIORef (rsCgpHealthy rs) True
      writeIORef (rsOrHealthy rs) True
      decision <- decideRoute rs
      decision `shouldBe` RouteToCgp
