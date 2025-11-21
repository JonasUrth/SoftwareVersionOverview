module Pages.Firmware exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (Country, Software, SoftwareType(..), Version, VersionDetail, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.Firmware exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, preventDefaultOn)
import Http
import Json.Decode as Decode
import Layouts.Default
import Page
import Request
import Shared
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared req
        , view = view shared req
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { versions : List Version
    , versionDetails : Dict Int VersionDetail
    , loading : Bool
    , error : Maybe String
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , versionDetails = Dict.empty
      , loading = True
      , error = Nothing
      }
    , Effect.batch
        [ if List.isEmpty shared.countries then
            Effect.fromShared Shared.RefreshCountries

          else
            Effect.none
        , if List.isEmpty shared.software then
            Effect.fromShared Shared.RefreshSoftware

          else
            Effect.none
        , if List.isEmpty shared.customers then
            Effect.fromShared Shared.RefreshCustomers

          else
            Effect.none
        , fetchVersions
        ]
    )


fetchVersions : Effect Msg
fetchVersions =
    Http.get
        { url = Endpoint.versions []
        , expect = Http.expectJson GotVersions (Decode.list versionDecoder)
        }
        |> Effect.fromCmd


fetchVersionDetail : Int -> Effect Msg
fetchVersionDetail versionId =
    Http.get
        { url = Endpoint.versions [ String.fromInt versionId ]
        , expect = Http.expectJson (GotVersionDetail versionId) versionDetailDecoder
        }
        |> Effect.fromCmd


-- UPDATE


type Msg
    = GotVersions (Result Http.Error (List Version))
    | GotVersionDetail Int (Result Http.Error VersionDetail)
    | NavigateToRoute Route.Route
    | NavigateToEpromHistory Int
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotVersions (Ok versions) ->
            let
                firmwareSoftwareIds =
                    shared.software
                        |> List.filter (\s -> s.type_ == Firmware)
                        |> List.map .id

                firmwareVersions =
                    versions
                        |> List.filter (\v -> List.member v.softwareId firmwareSoftwareIds)

                versionIdsToFetch =
                    firmwareVersions
                        |> List.map .id
                        |> List.filter (\id -> not (Dict.member id model.versionDetails))
            in
            ( { model | versions = versions, loading = False }
            , if List.isEmpty versionIdsToFetch then
                Effect.none

              else
                versionIdsToFetch
                    |> List.map fetchVersionDetail
                    |> Effect.batch
            )

        GotVersions (Err _) ->
            ( { model | loading = False, error = Just "Failed to load versions" }, Effect.none )

        GotVersionDetail versionId (Ok detail) ->
            ( { model | versionDetails = Dict.insert versionId detail model.versionDetails }
            , Effect.none
            )

        GotVersionDetail _ (Err _) ->
            ( model, Effect.none )

        NavigateToRoute route ->
            ( model, Effect.fromCmd (Request.pushRoute route req) )

        LogoutRequested ->
            ( model
            , Effect.fromCmd (Api.Auth.logout LogoutResponse)
            )

        LogoutResponse (Ok _) ->
            ( model
            , Effect.batch
                [ Effect.fromShared Shared.UserLoggedOut
                , Effect.fromCmd (Request.pushRoute Route.Login req)
                ]
            )

        LogoutResponse (Err _) ->
            -- Even if logout API fails, clear local state and navigate to login
            ( model
            , Effect.batch
                [ Effect.fromShared Shared.UserLoggedOut
                , Effect.fromCmd (Request.pushRoute Route.Login req)
                ]
            )

        NavigateToEpromHistory countryId ->
            ( model, Effect.fromCmd (Request.pushRoute (Route.Firmware__EpromHistory__CountryId_ { countryId = String.fromInt countryId }) req) )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


-- VIEW


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    Layouts.Default.view
        { shared = shared
        , req = req
        , pageTitle = "Firmware Overview - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Firmware Overview" ]
                ]
            , viewContent shared model
            ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewContent : Shared.Model -> Model -> Html Msg
viewContent shared model =
    if model.loading then
        div [ class "loading" ] [ text "Loading firmware data..." ]

    else
        case model.error of
            Just err ->
                div [ class "error" ] [ text err ]

            Nothing ->
                let
                    firmwareSoftware =
                        shared.software
                            |> List.filter (\s -> s.type_ == Firmware)
                            |> List.sortBy .name

                    countries =
                        shared.countries
                            |> List.sortBy .name
                in
                if List.isEmpty shared.software && List.isEmpty shared.countries then
                    div [ class "loading" ] [ text "Loading data..." ]

                else if List.isEmpty firmwareSoftware then
                    p [ class "empty" ] 
                        [ text ("No firmware software found. " ++ 
                            (if List.isEmpty shared.software then
                                "Please ensure you are logged in and software data is loaded."
                             else
                                "Found " ++ String.fromInt (List.length shared.software) ++ " software items, but none are firmware type."
                            ))
                        ]

                else if List.isEmpty countries then
                    p [ class "empty" ] [ text "No countries found." ]

                else
                    div [ class "table-container" ]
                        [ table [ class "firmware-table" ]
                            [ thead []
                                [ tr []
                                    ([ th [] [ text "Country" ] ]
                                        ++ List.map (\sw -> th [] [ text sw.name ]) firmwareSoftware
                                        ++ [ th [] [ text "Released By" ]
                                           , th [] [ text "Notes" ]
                                           , th [] [ text "Actions" ]
                                           ]
                                    )
                                ]
                            , tbody [] (List.map (viewCountryRow shared firmwareSoftware model) countries)
                            ]
                        ]


viewCountryRow : Shared.Model -> List Software -> Model -> Country -> Html Msg
viewCountryRow shared firmwareSoftware model country =
    let
        countryCustomerIds =
            shared.customers
                |> List.filter (\c -> c.countryId == country.id)
                |> List.map .id

        latestVersions =
            firmwareSoftware
                |> List.map
                    (\sw ->
                        findLatestVersionForCountry sw country countryCustomerIds model
                    )

        latestReleasedBy =
            latestVersions
                |> List.filterMap identity
                |> List.sortBy (\v -> v.releaseDate)
                |> List.reverse
                |> List.head
                |> Maybe.map .releasedByName
                |> Maybe.withDefault "-"
    in
    tr []
        ([ td [] [ text country.name ] ]
            ++ List.map
                (\maybeVersion ->
                    td []
                        [ text
                            (case maybeVersion of
                                Just version ->
                                    version.version

                                Nothing ->
                                    "-"
                            )
                        ]
                )
                latestVersions
            ++ [ td [] [ text latestReleasedBy ]
               , td [] [ text (Maybe.withDefault "-" country.firmwareReleaseNote) ]
               , td [ class "actions" ]
                    [ button
                        [ class "btn-small"
                        , onClick (NavigateToEpromHistory country.id)
                        ]
                        [ text "Eprom Ver. Hist." ]
                    ]
               ]
        )


findLatestVersionForCountry : Software -> Country -> List Int -> Model -> Maybe VersionDetail
findLatestVersionForCountry software country countryCustomerIds model =
    let
        -- Get all versions for this software
        softwareVersions =
            model.versions
                |> List.filter (\v -> v.softwareId == software.id)
                |> List.sortBy .releaseDate
                |> List.reverse

        -- Check each version detail to see if it has customers from this country
        findLatestInVersions versions =
            case versions of
                [] ->
                    Nothing

                version :: rest ->
                    case Dict.get version.id model.versionDetails of
                        Just detail ->
                            -- Check if this version has any customers from this country
                            if hasCountryCustomers detail countryCustomerIds then
                                Just detail

                            else
                                findLatestInVersions rest

                        Nothing ->
                            -- Version detail not loaded yet, skip
                            findLatestInVersions rest
    in
    findLatestInVersions softwareVersions


hasCountryCustomers : VersionDetail -> List Int -> Bool
hasCountryCustomers versionDetail countryCustomerIds =
    -- Check if any customer in the version detail matches the country's customer IDs
    versionDetail.customers
        |> List.any (\customer -> List.member customer.id countryCustomerIds)
