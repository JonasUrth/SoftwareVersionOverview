module Pages.Home_ exposing (Model, Msg, page)

import Api.Data exposing (Version)
import Gen.Params.Home_ exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, preventDefaultOn)
import Json.Decode as Decode
import Http
import Json.Decode as Decode
import Page
import Request
import Shared
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.element
        { init = init
        , update = update req
        , view = view shared req
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { recentVersions : List Version
    }


init : ( Model, Cmd Msg )
init =
    ( { recentVersions = [] }
    , fetchRecentVersions
    )


fetchRecentVersions : Cmd Msg
fetchRecentVersions =
    Http.get
        { url = "http://localhost:5000/api/versions"
        , expect = Http.expectJson GotVersions (Decode.list Api.Data.versionDecoder)
        }


-- UPDATE


type Msg
    = GotVersions (Result Http.Error (List Version))
    | NavigateToLogin
    | NavigateToRoute Route.Route
    | NavigateToVersion Int


update : Request.With Params -> Msg -> Model -> ( Model, Cmd Msg )
update req msg model =
    case msg of
        GotVersions (Ok versions) ->
            ( { model | recentVersions = List.take 10 versions }
            , Cmd.none
            )

        GotVersions (Err _) ->
            ( model, Cmd.none )

        NavigateToLogin ->
            ( model, Request.pushRoute Route.Login req )

        NavigateToRoute route ->
            ( model, Request.pushRoute route req )

        NavigateToVersion id ->
            ( model, Request.pushRoute (Route.Versions__Id_ { id = String.fromInt id }) req )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


-- VIEW


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = "Dashboard - BM Release Manager"
    , body =
        case shared.user of
            Nothing ->
                [ div [ class "container" ]
                    [ div [ class "hero" ]
                        [ h1 [] [ text "BM Release Manager" ]
                        , p [] [ text "Please log in to continue" ]
                        , a [ href (Route.toHref Route.Login), preventDefaultOn "click" (Decode.succeed ( NavigateToLogin, True )), class "btn-primary" ] [ text "Login" ]
                        ]
                    ]
                ]

            Just user ->
                [ div [ class "container" ]
                    [ h1 [] [ text ("Welcome, " ++ user.name ++ "!!") ]
                    , div [ class "dashboard-grid" ]
                        [ dashboardCard req "Countries" (String.fromInt (List.length shared.countries)) Route.Countries
                        , dashboardCard req "Customers" (String.fromInt (List.length shared.customers)) Route.Customers
                        , dashboardCard req "Software" (String.fromInt (List.length shared.software)) Route.Software
                        , dashboardCard req "Versions" (String.fromInt (List.length model.recentVersions)) Route.Versions
                        ]
                    , div [ class "section" ]
                        [ h2 [] [ text "Recent Releases" ]
                        , viewRecentVersions req model.recentVersions
                        ]
                    ]
                ]
    }


dashboardCard : Request.With Params -> String -> String -> Route.Route -> Html Msg
dashboardCard req title count route =
    a [ href (Route.toHref route), preventDefaultOn "click" (Decode.succeed ( NavigateToRoute route, True )), class "dashboard-card" ]
        [ h3 [] [ text title ]
        , div [ class "count" ] [ text count ]
        , p [] [ text "Manage →" ]
        ]


viewRecentVersions : Request.With Params -> List Version -> Html Msg
viewRecentVersions req versions =
    if List.isEmpty versions then
        p [ class "empty" ] [ text "No releases yet" ]

    else
        div [ class "table-container" ]
            [ table []
                [ thead []
                    [ tr []
                        [ th [] [ text "Software" ]
                        , th [] [ text "Version" ]
                        , th [] [ text "Status" ]
                        , th [] [ text "Released By" ]
                        , th [] [ text "Customers" ]
                        ]
                    ]
                , tbody [] (List.map (viewVersionRow req) versions)
                ]
            ]


viewVersionRow : Request.With Params -> Version -> Html Msg
viewVersionRow req version =
    tr []
        [ td [] [ text version.softwareName ]
        , td [] [ a [ href (Route.toHref (Route.Versions__Id_ { id = String.fromInt version.id })), preventDefaultOn "click" (Decode.succeed ( NavigateToVersion version.id, True )), class "link" ] [ text version.version ] ]
        , td [] [ span [ class ("badge " ++ statusClass version.releaseStatus) ] [ text (Api.Data.releaseStatusToString version.releaseStatus) ] ]
        , td [] [ text version.releasedBy ]
        , td [] [ text (String.fromInt version.customerCount) ]
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
