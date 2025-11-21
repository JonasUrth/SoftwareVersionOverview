port module Ports exposing (load, save)

import Json.Encode


port save : { key : String, value : Json.Encode.Value } -> Cmd msg


port load : (Json.Encode.Value -> msg) -> Sub msg

