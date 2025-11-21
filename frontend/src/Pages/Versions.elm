module Pages.Versions exposing (Model, Msg, page)

import Api.Data exposing (ReleaseStatus(..), Version, releaseStatusToString)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Versions exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (preventDefaultOn)
import Json.Decode as Decode
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
        { init = init shared
        , update = update shared req
        , view = view shared req
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { versions : List Version
    , loading : Bool
    , error : Maybe String
    }


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { versions = []
      , loading = True
      , error = Nothing
      }
    , fetchVersions shared.token
    )


fetchVersions : Maybe String -> Effect Msg
fetchVersions token =
    Http.request
        { method = "GET"
        , headers = authHeaders token
        , url = Endpoint.versions []
        , body = Http.emptyBody
        , expect = Http.expectJson GotVersions (Decode.list Api.Data.versionDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }
        |> Effect.fromCmd


authHeaders : Maybe String -> List Http.Header
authHeaders token =
    case token of
        Just t ->
            [ Http.header "Authorization" ("Basic " ++ t) ]

        Nothing ->
            []


-- UPDATE


type Msg
    = GotVersions (Result Http.Error (List Version))
    | Refresh
    | NavigateToNew
    | NavigateToVersion Int
    | NavigateToRoute Route.Route


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotVersions (Ok versions) ->
            ( { model | versions = versions, loading = False, error = Nothing }, Effect.none )

        GotVersions (Err _) ->
            ( { model | loading = False, error = Just "Failed to load versions" }, Effect.none )

        Refresh ->
            ( { model | loading = True }, fetchVersions shared.token )

        NavigateToNew ->
            ( model, Effect.fromCmd (Request.pushRoute Route.Versions__New req) )

        NavigateToVersion id ->
            ( model, Effect.fromCmd (Request.pushRoute (Route.Versions__Id_ { id = String.fromInt id }) req) )

        NavigateToRoute route ->
            ( model, Effect.fromCmd (Request.pushRoute route req) )


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
        , pageTitle = "Versions - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Versions" ]
                , a [ href (Route.toHref Route.Versions__New), preventDefaultOn "click" (Decode.succeed ( NavigateToNew, True )), class "btn-primary" ] [ text "+ Create Release" ]
                ]
            , viewContent model
            ]
        , onNavigate = NavigateToRoute
        }


viewContent : Model -> Html Msg
viewContent model =
    if model.loading then
        div [ class "loading" ] [ text "Loading versions..." ]

    else if List.isEmpty model.versions then
        p [ class "empty" ] [ text "No versions created yet. Create one to get started!" ]

    else
        div [ class "table-container" ]
            [ table []
                [ thead []
                    [ tr []
                        [ th [] [ text "Software" ]
                        , th [] [ text "Version" ]
                        , th [] [ text "Status" ]
                        , th [] [ text "Released By" ]
                        , th [] [ text "Release Date" ]
                        , th [] [ text "Customers" ]
                        ]
                    ]
                , tbody [] (List.map viewVersionRow model.versions)
                ]
            ]


viewVersionRow : Version -> Html Msg
viewVersionRow version =
    tr []
        [ td [] [ text version.softwareName ]
        , td []
            [ a [ href (Route.toHref (Route.Versions__Id_ { id = String.fromInt version.id })), preventDefaultOn "click" (Decode.succeed ( NavigateToVersion version.id, True )), class "link" ]
                [ text version.version ]
            ]
        , td []
            [ span [ class ("badge " ++ statusClass version.releaseStatus) ]
                [ text (releaseStatusToString version.releaseStatus) ]
            ]
        , td [] [ text version.releasedBy ]
        , td [] [ text version.releaseDate ]
        , td [] [ text (String.fromInt version.customerCount) ]
        ]


statusClass : ReleaseStatus -> String
statusClass status =
    case status of
        PreRelease ->
            "status-prerelease"

        Released ->
            "status-released"

        ProductionReady ->
            "status-production"
