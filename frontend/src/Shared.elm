module Shared exposing
    ( Flags
    , Model
    , Msg(..)
    , ReleaseHistoryState
    , init
    , subscriptions
    , update
    )

import Api.Auth
import Api.Data exposing (Country, Customer, Software, User)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Request exposing (Request)


-- FLAGS


type alias Flags =
    Decode.Value


-- MODEL


type alias Model =
    { user : Maybe User
    , token : Maybe String
    , countries : List Country
    , customers : List Customer
    , software : List Software
    , releaseHistoryState : Maybe ReleaseHistoryState
    }


type alias ReleaseHistoryState =
    { compactView : Bool
    , filterDate : String
    , filterReleasedBy : String
    , filterReleasedFor : String
    , filterNotes : String
    , filterStatus : String
    , scrollPosition : Float
    }


-- INIT


init : Request -> Flags -> ( Model, Cmd Msg )
init _ flags =
    let
        storage =
            flags
                |> Decode.decodeValue storageDecoder
                |> Result.toMaybe
                |> Maybe.withDefault { token = Nothing }
    in
    ( { user = Nothing
      , token = storage.token
      , countries = []
      , customers = []
      , software = []
      , releaseHistoryState = Nothing
      }
    , case storage.token of
        Just token ->
            -- Verify token with backend and restore session
            Api.Auth.checkAuth token GotAuthCheck

        Nothing ->
            Cmd.none
    )


-- UPDATE


type Msg
    = GotAuthCheck (Result Http.Error Api.Auth.CheckResponse)
    | GotCountries (Result Http.Error (List Country))
    | GotCustomers (Result Http.Error (List Customer))
    | GotSoftware (Result Http.Error (List Software))
    | UserLoggedIn User String
    | UserLoggedOut
    | RefreshCountries
    | RefreshCustomers
    | RefreshCustomersWithInactive Bool
    | RefreshSoftware
    | StorageLoaded Decode.Value
    | PrintPage
    | SaveReleaseHistoryState ReleaseHistoryState
    | ClearReleaseHistoryState


update : Request -> Msg -> Model -> ( Model, Cmd Msg )
update _ msg model =
    case msg of
        GotAuthCheck (Ok response) ->
            ( { model | user = response.user }
            , if response.authenticated then
                Cmd.batch
                    [ fetchCountries model.token
                    , fetchCustomers model.token False
                    , fetchSoftware model.token
                    ]

              else
                Cmd.none
            )

        GotAuthCheck (Err _) ->
            ( model, Cmd.none )

        GotCountries (Ok countries) ->
            ( { model | countries = countries }, Cmd.none )

        GotCountries (Err _) ->
            ( model, Cmd.none )

        GotCustomers (Ok customers) ->
            ( { model | customers = customers }, Cmd.none )

        GotCustomers (Err _) ->
            ( model, Cmd.none )

        GotSoftware (Ok software) ->
            ( { model | software = software }, Cmd.none )

        GotSoftware (Err _) ->
            ( model, Cmd.none )

        UserLoggedIn user token ->
            ( { model | user = Just user, token = Just token }
            , Cmd.batch
                [ save { token = Just token }
                , fetchCountries (Just token)
                , fetchCustomers (Just token) False
                , fetchSoftware (Just token)
                ]
            )

        UserLoggedOut ->
            ( { model
                | user = Nothing
                , token = Nothing
                , countries = []
                , customers = []
                , software = []
              }
            , save { token = Nothing }
            )

        StorageLoaded value ->
            let
                storage =
                    value
                        |> Decode.decodeValue storageDecoder
                        |> Result.toMaybe
                        |> Maybe.withDefault { token = Nothing }
            in
            ( { model | token = storage.token }, Cmd.none )

        RefreshCountries ->
            ( model, fetchCountries model.token )

        RefreshCustomers ->
            ( model, fetchCustomers model.token False )

        RefreshCustomersWithInactive includeInactive ->
            ( model, fetchCustomers model.token includeInactive )

        RefreshSoftware ->
            ( model, fetchSoftware model.token )

        PrintPage ->
            ( model, Ports.printPage () )

        SaveReleaseHistoryState state ->
            ( { model | releaseHistoryState = Just state }, Cmd.none )

        ClearReleaseHistoryState ->
            ( { model | releaseHistoryState = Nothing }, Cmd.none )


-- SUBSCRIPTIONS


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Ports.load StorageLoaded


-- HELPERS


-- STORAGE


type alias Storage =
    { token : Maybe String
    }


storageDecoder : Decode.Decoder Storage
storageDecoder =
    Decode.map Storage
        (Decode.maybe (Decode.field "token" Decode.string))


storageEncoder : Storage -> Encode.Value
storageEncoder storage =
    Encode.object
        [ ( "token"
          , case storage.token of
                Just token ->
                    Encode.string token

                Nothing ->
                    Encode.null
          )
        ]


save : Storage -> Cmd msg
save storage =
    Ports.save
        { key = "bm-release-manager"
        , value = storageEncoder storage
        }


authHeader : Maybe String -> List Http.Header
authHeader token =
    case token of
        Just t ->
            [ Http.header "Authorization" ("Basic " ++ t) ]

        Nothing ->
            []


fetchCountries : Maybe String -> Cmd Msg
fetchCountries token =
    Http.request
        { method = "GET"
        , headers = authHeader token
        , url = "http://localhost:5000/api/countries"
        , body = Http.emptyBody
        , expect = Http.expectJson GotCountries (Decode.list Api.Data.countryDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


fetchCustomers : Maybe String -> Bool -> Cmd Msg
fetchCustomers token includeInactive =
    let
        url =
            if includeInactive then
                "http://localhost:5000/api/customers?includeInactive=true"
            else
                "http://localhost:5000/api/customers"
    in
    Http.request
        { method = "GET"
        , headers = authHeader token
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson GotCustomers (Decode.list Api.Data.customerDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


fetchSoftware : Maybe String -> Cmd Msg
fetchSoftware token =
    Http.request
        { method = "GET"
        , headers = authHeader token
        , url = "http://localhost:5000/api/software"
        , body = Http.emptyBody
        , expect = Http.expectJson GotSoftware (Decode.list Api.Data.softwareDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }

