-- | Icon component using SVG sprites
module Straylight.Components.Icon
  ( icon
  , iconSm
  ) where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP


-- | Render an icon from the icons directory
icon :: forall w i. String -> HH.HTML w i
icon name =
  HH.img
    [ HP.src $ "icons/" <> name <> ".svg"
    , HP.class_ (HH.ClassName "icon")
    , HP.attr (HH.AttrName "alt") name
    ]

-- | Render a small icon
iconSm :: forall w i. String -> HH.HTML w i
iconSm name =
  HH.img
    [ HP.src $ "icons/" <> name <> ".svg"
    , HP.classes $ map HH.ClassName ["icon", "icon-sm"]
    , HP.attr (HH.AttrName "alt") name
    ]
