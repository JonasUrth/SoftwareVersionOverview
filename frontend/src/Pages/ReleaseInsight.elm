module Pages.ReleaseInsight exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (CustomerDetail, NoteDetail, ReleaseStatus(..), Software, Version, VersionDetail, releaseStatusToString, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.ReleaseInsight exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (preventDefaultOn)
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


type alias ReleaseInsightRow =
    { releaseDate : String
    , releasedBy : String
    , releasedFor : String
    , notes : String
    , releaseStatus : ReleaseStatus
    , softwareVersions : Dict Int String
    }


type alias Model =
    { versions : List Version
    , versionDetails : Dict Int VersionDetail
    , loading : Bool
    , error : Maybe String
    , softwareList : List Software
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , versionDetails = Dict.empty
      , loading = True
      , error = Nothing
      , softwareList = shared.software
      }
    , Effect.batch
        [ fetchVersions
        , if List.isEmpty shared.software then
            Effect.fromShared Shared.RefreshSoftware

          else
            Effect.none
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


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotVersions (Ok versions) ->
            let
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
            let
                updatedDetails =
                    Dict.insert versionId detail model.versionDetails

                allFetched =
                    List.length model.versions == Dict.size updatedDetails
            in
            ( { model | versionDetails = updatedDetails, loading = not allFetched }
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
        , pageTitle = "Release Insight - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Release Insight" ]
                , p [ class "subtitle" ] [ text "Complete list of all releases with history notes and customers" ]
                ]
            , div [ class "full-width-content" ]
                [ viewContent shared model
                ]
            ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewContent : Shared.Model -> Model -> Html Msg
viewContent shared model =
    if model.loading then
        div [ class "loading" ] [ text "Loading releases..." ]

    else
        case model.error of
            Just err ->
                div [ class "error" ] [ text err ]

            Nothing ->
                let
                    softwareList =
                        if List.isEmpty model.softwareList then
                            shared.software

                        else
                            model.softwareList

                    rows =
                        buildReleaseInsightRows model.versions model.versionDetails
                in
                if List.isEmpty rows then
                    p [ class "empty" ] [ text "No releases found." ]

                else
                    viewReleaseTable softwareList rows


buildReleaseInsightRows : List Version -> Dict Int VersionDetail -> List ReleaseInsightRow
buildReleaseInsightRows versions versionDetails =
    versions
        |> List.filterMap
            (\version ->
                Dict.get version.id versionDetails
                    |> Maybe.map
                        (\detail ->
                            if List.isEmpty detail.customers then
                                -- If no customers, create one row with empty customer
                                [ { releaseDate = formatDate detail.releaseDate
                                  , releasedBy = detail.releasedByName
                                  , releasedFor = ""
                                  , notes = formatNotes detail.notes
                                  , releaseStatus = detail.releaseStatus
                                  , softwareVersions = Dict.singleton detail.softwareId detail.version
                                  }
                                ]

                            else
                                -- Create one row per customer
                                List.map
                                    (\customer ->
                                        { releaseDate = formatDate detail.releaseDate
                                        , releasedBy = detail.releasedByName
                                        , releasedFor = customer.name
                                        , notes = formatNotesForCustomer customer.id detail.notes
                                        , releaseStatus = detail.releaseStatus
                                        , softwareVersions = Dict.singleton detail.softwareId detail.version
                                        }
                                    )
                                    detail.customers
                        )
            )
        |> List.concat


formatNotes : List NoteDetail -> String
formatNotes notes =
    notes
        |> List.map .note
        |> String.join "\n"


formatNotesForCustomer : Int -> List NoteDetail -> String
formatNotesForCustomer customerId notes =
    notes
        |> List.filter (\note -> List.any (\c -> c.id == customerId) note.customers)
        |> List.map .note
        |> String.join "\n"


formatDate : String -> String
formatDate dateString =
    dateString
        |> String.split "T"
        |> List.head
        |> Maybe.withDefault dateString


viewReleaseTable : List Software -> List ReleaseInsightRow -> Html Msg
viewReleaseTable softwareList rows =
    div [ class "table-container table-container-fullwidth", style "overflow-x" "auto" ]
        [ table [ class "release-insight-table" ]
            [ thead []
                [ tr []
                    ([ th [] [ text "Release Date" ]
                     ]
                        ++ List.map (\sw -> th [] [ text sw.name ]) softwareList
                        ++ [ th [] [ text "Released By" ]
                           , th [] [ text "Released For" ]
                           , th [] [ text "Notes" ]
                           , th [] [ text "Release Status" ]
                           ]
                    )
                ]
            , tbody [] (List.map (viewReleaseRow softwareList) rows)
            ]
        ]


viewReleaseRow : List Software -> ReleaseInsightRow -> Html Msg
viewReleaseRow softwareList row =
    tr []
        ([ td [] [ text row.releaseDate ]
         ]
            ++ List.map
                (\sw ->
                    td []
                        [ text
                            (Dict.get sw.id row.softwareVersions
                                |> Maybe.withDefault ""
                            )
                        ]
                )
                softwareList
            ++ [ td [] [ text row.releasedBy ]
               , td [] [ text row.releasedFor ]
               , td [ style "white-space" "pre-wrap", style "max-width" "400px" ] [ text row.notes ]
               , td []
                    [ span [ class ("badge " ++ statusClass row.releaseStatus) ]
                        [ text (releaseStatusToString row.releaseStatus) ]
                    ]
               ]
        )


statusClass : ReleaseStatus -> String
statusClass status =
    case status of
        PreRelease ->
            "status-prerelease"

        Released ->
            "status-released"

        ProductionReady ->
            "status-production"
