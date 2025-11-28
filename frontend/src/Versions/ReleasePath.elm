module Versions.ReleasePath exposing
    ( Request
    , Status(..)
    , evaluate
    , initialStatus
    , view
    )

import Api.Data exposing (Customer, ReleasePathCheckResponse, ReleaseStatus(..), Software, SoftwareType(..))
import Html exposing (Html, div, strong, text)
import Html.Attributes exposing (class, style)
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


view : Status -> Maybe Software -> List Customer -> List Int -> Html msg
view status maybeSoftware allCustomers selectedCustomerIds =
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
                        [ viewSuccessMessage maybeSoftware allCustomers selectedCustomerIds ]

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


viewSuccessMessage : Maybe Software -> List Customer -> List Int -> Html msg
viewSuccessMessage maybeSoftware allCustomers selectedCustomerIds =
    let
        selectedCustomers =
            allCustomers
                |> List.filter (\c -> List.member c.id selectedCustomerIds)
                |> List.sortBy .name
        
        isFirmware =
            case maybeSoftware of
                Just software ->
                    software.type_ == Firmware
                
                Nothing ->
                    False
        
        isWindows =
            case maybeSoftware of
                Just software ->
                    software.type_ == Windows
                
                Nothing ->
                    False
    in
    div [ class "success" ]
        [ text "Release files validated."
        , if isFirmware then
            viewCountryList selectedCustomers
          else if isWindows then
            viewCustomerList selectedCustomers
          else
            text ""
        ]


viewCountryList : List Customer -> Html msg
viewCountryList customers =
    let
        countries =
            customers
                |> List.map (\c -> c.country.name)
                |> List.foldr
                    (\countryName acc ->
                        if List.member countryName acc then
                            acc
                        else
                            countryName :: acc
                    )
                    []
                |> List.sort
    in
    if List.isEmpty countries then
        text ""
    else
        div [ style "margin-top" "0.5rem" ]
            [ strong [] [ text "Countries: " ]
            , text (String.join ", " countries)
            ]


viewCustomerList : List Customer -> Html msg
viewCustomerList customers =
    if List.isEmpty customers then
        text ""
    else
        div [ style "margin-top" "0.5rem" ]
            [ strong [] [ text "Customers: " ]
            , text (String.join ", " (List.map .name customers))
            ]


