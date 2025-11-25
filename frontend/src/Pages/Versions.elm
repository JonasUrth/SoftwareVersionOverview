module Pages.Versions exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (ReleaseStatus(..), Version, releaseStatusLabel)
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
        { init = init shared req
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


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , loading = False
      , error = Nothing
      }
    , case shared.user of
        Just _ ->
            fetchVersions shared.token

        Nothing ->
            Effect.none
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
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())


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
        , pageTitle = "Versions - BM Release Manager"
        , pageBody =
            case shared.user of
                Nothing ->
                    [ div [ class "container" ]
                        [ div [ class "hero" ]
                            [ h1 [] [ text "BM Release Manager" ]
                            , p [] [ text "Please log in to continue" ]
                            , a
                                [ href (Route.toHref Route.Login)
                                , preventDefaultOn "click" (Decode.succeed ( NavigateToRoute Route.Login, True ))
                                , class "btn-primary"
                                ]
                                [ text "Login" ]
                            ]
                        ]
                    ]

                Just _ ->
                    [ div [ class "header" ]
                        [ h1 [] [ text "Versions release overview" ]
                        , a [ href (Route.toHref Route.Versions__New), preventDefaultOn "click" (Decode.succeed ( NavigateToNew, True )), class "btn-primary" ] [ text "+ Create Release" ]
                        ]
                    , viewContent model
                    ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
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
                [ text (releaseStatusLabel version.releaseStatus) ]
            ]
        , td [] [ text version.releasedBy ]
        , td [] [ text (formatDateTime version.releaseDate) ]
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

        CustomPerCustomer ->
            "status-custom"

        Canceled ->
            "status-canceled"


formatDateTime : String -> String
formatDateTime dateTimeStr =
    case String.split "T" dateTimeStr of
        [ datePart, timePartWithSeconds ] ->
            let
                formattedDate =
                    case String.split "-" datePart of
                        [ year, month, day ] ->
                            let
                                dayFormatted =
                                    case String.toInt day of
                                        Just d ->
                                            String.fromInt d

                                        Nothing ->
                                            day
                            in
                            dayFormatted ++ " " ++ monthName month ++ " " ++ year

                        _ ->
                            datePart

                formattedTime =
                    case String.split ":" timePartWithSeconds of
                        hour :: minute :: _ ->
                            hour ++ ":" ++ minute

                        _ ->
                            timePartWithSeconds
            in
            formattedDate ++ " " ++ formattedTime

        _ ->
            dateTimeStr


monthName : String -> String
monthName month =
    case month of
        "01" ->
            "Jan"

        "02" ->
            "Feb"

        "03" ->
            "Mar"

        "04" ->
            "Apr"

        "05" ->
            "May"

        "06" ->
            "Jun"

        "07" ->
            "Jul"

        "08" ->
            "Aug"

        "09" ->
            "Sep"

        "10" ->
            "Oct"

        "11" ->
            "Nov"

        "12" ->
            "Dec"

        _ ->
            month
