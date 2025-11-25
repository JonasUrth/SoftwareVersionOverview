module Versions.ReleasePath exposing
    ( Request
    , Status(..)
    , evaluate
    , initialStatus
    , view
    )

import Api.Data exposing (ReleasePathCheckResponse, ReleaseStatus(..))
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import String


type alias Request =
    { softwareId : Int
    , version : String
    , customerIds : List Int
    }


type Status
    = NotRequired
    | MissingInfo String
    | Checking
    | Result ReleasePathCheckResponse
    | Error String


initialStatus : Status
initialStatus =
    NotRequired


evaluate : ReleaseStatus -> Int -> String -> List Int -> ( Status, Maybe Request )
evaluate releaseStatus softwareId version customerIds =
    if releaseStatus /= ProductionReady then
        ( NotRequired, Nothing )

    else if softwareId <= 0 then
        ( MissingInfo "Select a software to validate release files.", Nothing )

    else if String.isEmpty (String.trim version) then
        ( MissingInfo "Enter a version number to validate release files.", Nothing )

    else
        ( Checking
        , Just
            { softwareId = softwareId
            , version = version
            , customerIds = customerIds
            }
        )


view : Status -> Html msg
view status =
    case status of
        NotRequired ->
            text ""

        MissingInfo message ->
            div [ class "help-text warning" ] [ text message ]

        Checking ->
            div [ class "help-text" ] [ text "Checking release file location..." ]

        Result response ->
            let
                errorViews =
                    response.errors
                        |> List.map (\msg -> div [ class "error" ] [ text msg ])

                warningViews =
                    response.warnings
                        |> List.map (\msg -> div [ class "warning" ] [ text msg ])

                successView =
                    if response.isValid && List.isEmpty response.errors then
                        [ div [ class "success" ] [ text "Release files validated." ] ]

                    else
                        []
                blocks =
                    errorViews ++ warningViews ++ successView
            in
            if List.isEmpty blocks then
                text ""

            else
                div [] blocks

        Error message ->
            div [ class "warning" ] [ text message ]


