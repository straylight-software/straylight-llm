{- config.dhall

   Default gateway configuration instance.
   
   Usage:
     dhall resolve --file config.dhall
     dhall-to-json --file config.dhall > config.json
     
   Override example:
     let base = ./config.dhall
     in  base // { port = 9090, logLevel = LogLevel.Debug }
-}

let Config = ./Config.dhall

in  Config.defaultConfig
