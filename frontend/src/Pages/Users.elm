module Pages.Users exposing (view)

import Html exposing (..)
import Html.Attributes exposing (..)
import View exposing (View)


view : View msg
view =
    { title = "Users - BM Release Manager"
    , body =
        [ div [ class "container" ]
            [ h1 [] [ text "Users" ]
            , p [ class "empty" ] [ text "User management coming soon..." ]
            ]
        ]
    }
