module Api.Auth exposing (..)

import Api.Data exposing (User, userDecoder)
import Api.Endpoint as Endpoint
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type alias LoginRequest =
    { username : String
    , password : String
    }


type alias LoginResponse =
    { success : Bool
    , message : String
    , user : Maybe User
    , token : Maybe String
    }


loginResponseDecoder : Decoder LoginResponse
loginResponseDecoder =
    Decode.map4 LoginResponse
        (Decode.field "success" Decode.bool)
        (Decode.field "message" Decode.string)
        (Decode.maybe (Decode.field "user" userDecoder))
        (Decode.maybe (Decode.field "token" Decode.string))


login : LoginRequest -> (Result Http.Error LoginResponse -> msg) -> Cmd msg
login credentials toMsg =
    Http.request
        { method = "POST"
        , headers = []
        , url = Endpoint.auth [ "login" ]
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "username", Encode.string credentials.username )
                    , ( "password", Encode.string credentials.password )
                    ]
        , expect = Http.expectJson toMsg loginResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


logout : (Result Http.Error () -> msg) -> Cmd msg
logout toMsg =
    Http.post
        { url = Endpoint.auth [ "logout" ]
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        }


type alias CheckResponse =
    { authenticated : Bool
    , user : Maybe User
    }


checkResponseDecoder : Decoder CheckResponse
checkResponseDecoder =
    Decode.map2 CheckResponse
        (Decode.field "authenticated" Decode.bool)
        (Decode.maybe (Decode.field "user" userDecoder))


checkAuth : String -> (Result Http.Error CheckResponse -> msg) -> Cmd msg
checkAuth token toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Basic " ++ token) ]
        , url = Endpoint.auth [ "check" ]
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg checkResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }

