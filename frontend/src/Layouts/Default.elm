module Layouts.Default exposing (view)

import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, preventDefaultOn)
import Json.Decode as Decode
import Request
import Shared
import View exposing (View)


type alias Props msg params =
    { shared : Shared.Model
    , req : Request.With params
    , pageTitle : String
    , pageBody : List (Html msg)
    , onNavigate : Route.Route -> msg
    }


view : Props msg params -> View msg
view props =
    { title = props.pageTitle
    , body =
        [ viewNav props.shared props.req props.onNavigate
        , div [ class "container" ] props.pageBody
        ]
    }


viewNav : Shared.Model -> Request.With params -> (Route.Route -> msg) -> Html msg
viewNav shared req onNavigate =
    nav [ class "navbar" ]
        [ div [ class "nav-container" ]
            [ a
                [ href (Route.toHref Route.Home_)
                , preventDefaultOn "click" (Decode.succeed ( onNavigate Route.Home_, True ))
                , class "nav-brand"
                ]
                [ text "BM Release Manager" ]
            , div [ class "nav-links" ]
                [ navLink req Route.Home_ "Home" onNavigate
                , navLink req Route.Countries "Countries" onNavigate
                , navLink req Route.Customers "Customers" onNavigate
                , navLink req Route.Software "Software" onNavigate
                , navLink req Route.Versions "Versions" onNavigate
                , navLink req Route.Firmware "Firmware" onNavigate
                ]
            , case shared.user of
                Just user ->
                    div [ class "nav-user" ]
                        [ span [] [ text user.name ]
                        , button
                            [ class "btn-small btn-secondary"
                            , onClick (onNavigate Route.Login)
                            ]
                            [ text "Logout" ]
                        ]

                Nothing ->
                    text ""
            ]
        ]


navLink : Request.With params -> Route.Route -> String -> (Route.Route -> msg) -> Html msg
navLink req route label onNavigate =
    a
        [ href (Route.toHref route)
        , preventDefaultOn "click" (Decode.succeed ( onNavigate route, True ))
        , class "nav-link"
        ]
        [ text label ]

