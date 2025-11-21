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
    , onLogout : msg
    }


view : Props msg params -> View msg
view props =
    { title = props.pageTitle
    , body =
        [ div [ class "layout-container" ]
            [ viewSidebar props.shared props.onNavigate props.onLogout
            , div [ class "main-content" ]
                [ div [ class "container" ] props.pageBody ]
            ]
        ]
    }


viewSidebar : Shared.Model -> (Route.Route -> msg) -> msg -> Html msg
viewSidebar shared onNavigate onLogout =
    aside [ class "sidebar" ]
        [ div [ class "sidebar-content" ]
            [ a
                [ href (Route.toHref Route.Home_)
                , preventDefaultOn "click" (Decode.succeed ( onNavigate Route.Home_, True ))
                , class "sidebar-brand"
                ]
                [ text "BM Release Manager" ]
            , nav [ class "sidebar-nav" ]
                [ navLink Route.Home_ "Dashboard" onNavigate
                , navLink Route.Countries "Countries" onNavigate
                , navLink Route.Customers "Customers" onNavigate
                , navLink Route.Software "Software" onNavigate
                , navLink Route.Versions "Versions" onNavigate
                , navSection "Release Insights"
                    [ navSubLink Route.Firmware "Firmware" onNavigate                    
                    ]
                ]
            , case shared.user of
                Just user ->
                    div [ class "sidebar-user" ]
                        [ span [ class "sidebar-user-name" ] [ text user.name ]
                        , button
                            [ class "btn-small btn-secondary"
                            , onClick onLogout
                            ]
                            [ text "Logout" ]
                        ]

                Nothing ->
                    text ""
            ]
        ]


navLink : Route.Route -> String -> (Route.Route -> msg) -> Html msg
navLink route label onNavigate =
    a
        [ href (Route.toHref route)
        , preventDefaultOn "click" (Decode.succeed ( onNavigate route, True ))
        , class "sidebar-link"
        ]
        [ text label ]


navSubLink : Route.Route -> String -> (Route.Route -> msg) -> Html msg
navSubLink route label onNavigate =
    a
        [ href (Route.toHref route)
        , preventDefaultOn "click" (Decode.succeed ( onNavigate route, True ))
        , class "sidebar-sublink"
        ]
        [ text label ]


navSection : String -> List (Html msg) -> Html msg
navSection title links =
    div [ class "sidebar-section" ]
        [ span [ class "sidebar-section-title" ] [ text title ]
        , div [ class "sidebar-sub-links" ] links
        ]


