module Pages.Firmware.EpromHistory.CountryId_ exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (Country, SoftwareType(..), Version, VersionDetail, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.Firmware.EpromHistory.CountryId_ exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Json.Decode as Decode
import Layouts.Default
import Page
import Request
import Shared
import View exposing (View)
import String


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update req
        , view = view shared req
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { countryId : Int
    , country : Maybe Country
    , versions : List Version
    , versionDetails : Dict Int VersionDetail
    , loading : Bool
    , error : Maybe String
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        countryId =
            String.toInt req.params.countryId |> Maybe.withDefault 0

        country =
            shared.countries
                |> List.filter (\c -> c.id == countryId)
                |> List.head
    in
    ( { countryId = countryId
      , country = country
      , versions = []
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
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        GotVersions (Ok versions) ->
            let
                firmwareSoftwareIds =
                    -- We'll filter in the view using shared.software
                    []

                versionIdsToFetch =
                    versions
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
        , pageTitle = "Eprom Version History - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 []
                    [ text
                        ("Eprom Version History"
                            ++ (case model.country of
                                    Just c ->
                                        " - " ++ c.name

                                    Nothing ->
                                        ""
                               )
                        )
                    ]
                , a
                    [ href (Route.toHref Route.Firmware)
                    , class "btn-secondary"
                    ]
                    [ text "← Back to Firmware Overview" ]
                ]
            , viewContent shared model
            ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewContent : Shared.Model -> Model -> Html Msg
viewContent shared model =
    if model.loading then
        div [ class "loading" ] [ text "Loading eprom version history..." ]

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

                    countryCustomerIds =
                        shared.customers
                            |> List.filter (\c -> c.countryId == model.countryId)
                            |> List.map .id

                    -- Filter versions to only those that have customers from this country
                    relevantVersions =
                        model.versions
                            |> List.filter
                                (\v ->
                                    List.member v.softwareId (List.map .id firmwareSoftware)
                                        && (case Dict.get v.id model.versionDetails of
                                                Just detail ->
                                                    hasCountryCustomers detail countryCustomerIds

                                                Nothing ->
                                                    False
                                           )
                                )
                            |> List.sortBy .releaseDate
                            |> List.reverse
                in
                if List.isEmpty relevantVersions then
                    p [ class "empty" ] [ text "No eprom version history found for this country." ]

                else
                    div [ class "table-container" ]
                        [ table []
                            [ thead []
                                [ tr []
                                    [ th [] [ text "Software" ]
                                    , th [] [ text "Version" ]
                                    , th [] [ text "Release Date" ]
                                    , th [] [ text "Released By" ]
                                    , th [] [ text "Status" ]
                                    , th [] [ text "Notes" ]
                                    ]
                                ]
                            , tbody [] (List.map (viewVersionRow model) relevantVersions)
                            ]
                        ]


viewVersionRow : Model -> Version -> Html Msg
viewVersionRow model version =
    let
        maybeDetail =
            Dict.get version.id model.versionDetails

        releasedBy =
            maybeDetail
                |> Maybe.map .releasedByName
                |> Maybe.withDefault version.releasedBy

        notesText =
            maybeDetail
                |> Maybe.map (.notes >> List.map .note >> String.join "; ")
                |> Maybe.withDefault "-"
    in
    tr []
        [ td [] [ text version.softwareName ]
        , td [] [ text version.version ]
        , td [] [ text version.releaseDate ]
        , td [] [ text releasedBy ]
        , td []
            [ span [ class ("badge " ++ statusClass version.releaseStatus) ]
                [ text (Api.Data.releaseStatusToString version.releaseStatus) ]
            ]
        , td [] [ text notesText ]
        ]


statusClass : Api.Data.ReleaseStatus -> String
statusClass status =
    case status of
        Api.Data.PreRelease ->
            "status-prerelease"

        Api.Data.Released ->
            "status-released"

        Api.Data.ProductionReady ->
            "status-production"


hasCountryCustomers : VersionDetail -> List Int -> Bool
hasCountryCustomers versionDetail countryCustomerIds =
    versionDetail.customers
        |> List.any (\customer -> List.member customer.id countryCustomerIds)
