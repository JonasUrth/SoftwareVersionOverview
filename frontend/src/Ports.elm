port module Ports exposing (load, save, printPage, saveScrollPosition, restoreScrollPosition, onScrollPositionSaved)

import Json.Encode


port save : { key : String, value : Json.Encode.Value } -> Cmd msg


port load : (Json.Encode.Value -> msg) -> Sub msg


port printPage : () -> Cmd msg


port saveScrollPosition : () -> Cmd msg


port restoreScrollPosition : Float -> Cmd msg


port onScrollPositionSaved : (Float -> msg) -> Sub msg

