-- | Splash screen dismiss logic
module Straylight.Components.Splash
  ( dismiss
  ) where

import Prelude

import Effect (Effect)

foreign import dismissImpl :: Effect Unit

-- | Dismiss the splash screen
dismiss :: Effect Unit
dismiss = dismissImpl
