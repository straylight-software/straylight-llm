{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                         // straylight // main
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "The sky above the port was the color of television,
    tuned to a dead channel."

                                                               — Neuromancer

   straylight-llm gateway entry point.
-}
module Main (main) where

import Straylight.Config (loadConfig)
import Straylight.Server (runServer)


main :: IO ()
main = do
  cfg <- loadConfig
  runServer cfg
