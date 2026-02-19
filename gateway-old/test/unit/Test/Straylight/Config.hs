{-# LANGUAGE OverloadedStrings #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                 // test // straylight // config
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

module Test.Straylight.Config (spec) where

import Test.Hspec

import Straylight.Config


spec :: Spec
spec = do
  describe "defaultConfig" $ do
    it "has port 4000" $
      cfgPort defaultConfig `shouldBe` 4000

    it "has host 0.0.0.0" $
      cfgHost defaultConfig `shouldBe` "0.0.0.0"

    it "has LogInfo level" $
      cfgLogLevel defaultConfig `shouldBe` LogInfo

    it "has CGP disabled by default" $
      cgpEnabled defaultConfig `shouldBe` False

    it "has OpenRouter disabled by default (no API key)" $
      openRouterEnabled defaultConfig `shouldBe` False

  describe "CgpConfig" $ do
    it "empty apiBase means disabled" $
      let cfg = defaultConfig { cfgCgp = (cfgCgp defaultConfig) { cgpApiBase = "" } }
      in cgpEnabled cfg `shouldBe` False

    it "non-empty apiBase means enabled" $
      let cfg = defaultConfig { cfgCgp = (cfgCgp defaultConfig) { cgpApiBase = "http://localhost:8000" } }
      in cgpEnabled cfg `shouldBe` True

  describe "OpenRouterConfig" $ do
    it "no API key means disabled" $
      let cfg = defaultConfig { cfgOpenRouter = (cfgOpenRouter defaultConfig) { orApiKey = Nothing } }
      in openRouterEnabled cfg `shouldBe` False

    it "empty API key means disabled" $
      let cfg = defaultConfig { cfgOpenRouter = (cfgOpenRouter defaultConfig) { orApiKey = Just "" } }
      in openRouterEnabled cfg `shouldBe` False

    it "non-empty API key means enabled" $
      let cfg = defaultConfig { cfgOpenRouter = (cfgOpenRouter defaultConfig) { orApiKey = Just "sk-or-test" } }
      in openRouterEnabled cfg `shouldBe` True

  describe "LogLevel" $ do
    it "LogDebug is the lowest level" $
      LogDebug < LogInfo `shouldBe` True

    it "LogInfo < LogWarning" $
      LogInfo < LogWarning `shouldBe` True

    it "LogWarning < LogError" $
      LogWarning < LogError `shouldBe` True

    it "LogError < LogCritical" $
      LogError < LogCritical `shouldBe` True
