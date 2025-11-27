module Pages.Versions exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (ReleaseStatus(..), Version, releaseStatusLabel)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Versions exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
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


type SortColumn
    = SortSoftware
    | SortVersion
    | SortStatus
    | SortReleasedBy
    | SortReleaseDate
    | SortCustomers


type SortDirection
    = Ascending
    | Descending


type alias Model =
    { versions : List Version
    , loading : Bool
    , error : Maybe String
    , filterSoftware : String
    , filterVersion : String
    , filterStatus : String
    , filterReleasedBy : String
    , filterReleaseDate : String
    , filterCustomers : String
    , sortColumn : Maybe SortColumn
    , sortDirection : SortDirection
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , loading = False
      , error = Nothing
      , filterSoftware = ""
      , filterVersion = ""
      , filterStatus = ""
      , filterReleasedBy = ""
      , filterReleaseDate = ""
      , filterCustomers = ""
      , sortColumn = Nothing
      , sortDirection = Descending
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
    | FilterSoftwareChanged String
    | FilterVersionChanged String
    | FilterStatusChanged String
    | FilterReleasedByChanged String
    | FilterReleaseDateChanged String
    | FilterCustomersChanged String
    | SortColumnClicked SortColumn


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

        FilterSoftwareChanged value ->
            ( { model | filterSoftware = value }, Effect.none )

        FilterVersionChanged value ->
            ( { model | filterVersion = value }, Effect.none )

        FilterStatusChanged value ->
            ( { model | filterStatus = value }, Effect.none )

        FilterReleasedByChanged value ->
            ( { model | filterReleasedBy = value }, Effect.none )

        FilterReleaseDateChanged value ->
            ( { model | filterReleaseDate = value }, Effect.none )

        FilterCustomersChanged value ->
            ( { model | filterCustomers = value }, Effect.none )

        SortColumnClicked column ->
            let
                newDirection =
                    case model.sortColumn of
                        Just currentColumn ->
                            if currentColumn == column then
                                case model.sortDirection of
                                    Ascending ->
                                        Descending

                                    Descending ->
                                        Ascending

                            else
                                Ascending

                        Nothing ->
                            Ascending
            in
            ( { model | sortColumn = Just column, sortDirection = newDirection }, Effect.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


-- FILTER AND SORT


filterVersions : Model -> List Version -> List Version
filterVersions model versions =
    versions
        |> List.filter
            (\version ->
                let
                    softwareMatch =
                        String.isEmpty model.filterSoftware
                            || String.contains (String.toLower model.filterSoftware) (String.toLower version.softwareName)

                    versionMatch =
                        String.isEmpty model.filterVersion
                            || String.contains (String.toLower model.filterVersion) (String.toLower version.version)

                    statusMatch =
                        String.isEmpty model.filterStatus
                            || String.contains (String.toLower model.filterStatus) (String.toLower (releaseStatusLabel version.releaseStatus))

                    releasedByMatch =
                        String.isEmpty model.filterReleasedBy
                            || String.contains (String.toLower model.filterReleasedBy) (String.toLower version.releasedBy)

                    releaseDateMatch =
                        String.isEmpty model.filterReleaseDate
                            || String.contains (String.toLower model.filterReleaseDate) (String.toLower (formatDateTime version.releaseDate))

                    customersMatch =
                        String.isEmpty model.filterCustomers
                            || String.contains (String.toLower model.filterCustomers) (String.toLower (String.fromInt version.customerCount))
                in
                softwareMatch && versionMatch && statusMatch && releasedByMatch && releaseDateMatch && customersMatch
            )


sortVersions : Model -> List Version -> List Version
sortVersions model versions =
    case model.sortColumn of
        Just column ->
            let
                compareVersions v1 v2 =
                    case column of
                        SortSoftware ->
                            compare (String.toLower v1.softwareName) (String.toLower v2.softwareName)

                        SortVersion ->
                            compare (String.toLower v1.version) (String.toLower v2.version)

                        SortStatus ->
                            compare (releaseStatusLabel v1.releaseStatus) (releaseStatusLabel v2.releaseStatus)

                        SortReleasedBy ->
                            compare (String.toLower v1.releasedBy) (String.toLower v2.releasedBy)

                        SortReleaseDate ->
                            compare v1.releaseDate v2.releaseDate

                        SortCustomers ->
                            compare v1.customerCount v2.customerCount

                sorted =
                    List.sortWith compareVersions versions
            in
            case model.sortDirection of
                Ascending ->
                    sorted

                Descending ->
                    List.reverse sorted

        Nothing ->
            versions


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
        let
            filteredAndSorted =
                model.versions
                    |> filterVersions model
                    |> sortVersions model
        in
        div [ class "table-container" ]
            [ table [ class "versions-table" ]
                [ thead []
                    [ tr []
                        [ viewSortableHeader model SortSoftware "Software" []
                        , viewSortableHeader model SortVersion "Version" []
                        , viewSortableHeader model SortStatus "Status" []
                        , viewSortableHeader model SortReleasedBy "Released By" []
                        , viewSortableHeader model SortReleaseDate "Release Date" []
                        , viewSortableHeader model SortCustomers "Customers" []
                        ]
                    , tr [ class "filter-row" ]
                        [ viewFilterInputCell model SortSoftware [] (filterInput model.filterSoftware FilterSoftwareChanged)
                        , viewFilterInputCell model SortVersion [] (filterInput model.filterVersion FilterVersionChanged)
                        , viewFilterInputCell model SortStatus [] (filterInput model.filterStatus FilterStatusChanged)
                        , viewFilterInputCell model SortReleasedBy [] (filterInput model.filterReleasedBy FilterReleasedByChanged)
                        , viewFilterInputCell model SortReleaseDate [] (filterInput model.filterReleaseDate FilterReleaseDateChanged)
                        , viewFilterInputCell model SortCustomers [] (filterInput model.filterCustomers FilterCustomersChanged)
                        ]
                    ]
                , tbody []
                    (if List.isEmpty filteredAndSorted then
                        [ tr []
                            [ td [ colspan 6, style "text-align" "center", style "padding" "2rem", style "color" "#64748b" ]
                                [ text "No versions match the current filters." ]
                            ]
                        ]

                     else
                        List.map viewVersionRow filteredAndSorted
                    )
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


viewSortableHeader : Model -> SortColumn -> String -> List (Attribute Msg) -> Html Msg
viewSortableHeader model column label attrs =
    let
        headerAttrs =
            [ onClick (SortColumnClicked column)
            , style "cursor" "pointer"
            , style "user-select" "none"
            ]
                ++ attrs
    in
    th headerAttrs
        [ text label ]


viewFilterInputCell : Model -> SortColumn -> List (Attribute Msg) -> Html Msg -> Html Msg
viewFilterInputCell model column attrs inputField =
    let
        isActive =
            model.sortColumn == Just column

        indicatorText =
            if isActive then
                case model.sortDirection of
                    Ascending ->
                        "▲"

                    Descending ->
                        "▼"

            else
                "▲"

        indicatorClass =
            String.join " "
                ([ "sort-indicator"
                 , "sort-indicator-button"
                 ]
                    ++ (if isActive then
                            [ "sort-indicator-active" ]

                        else
                            [ "sort-indicator-inactive" ]
                       )
                )
    in
    th attrs
        [ div [ class "filter-cell" ]
            [ inputField
            , span
                [ class indicatorClass
                , title "Change sort order"
                , onClick (SortColumnClicked column)
                ]
                [ text indicatorText ]
            ]
        ]


filterInput : String -> (String -> Msg) -> Html Msg
filterInput value_ onChange =
    let
        hasFilter =
            not (String.isEmpty (String.trim value_))

        inputAttrs =
            [ type_ "text"
            , placeholder "Filter..."
            , value value_
            , onInput onChange
            , style "width" "100%"
            , style "padding" "4px"
            , style "padding-right" "2rem"
            , style "box-sizing" "border-box"
            ]
                ++ (if hasFilter then
                        [ style "border-color" "#dc2626"
                        , style "background-color" "#fff5f5"
                        ]

                    else
                        []
                   )
    in
    div
        [ style "position" "relative"
        , style "display" "flex"
        ]
        [ input inputAttrs []
        , button
            [ type_ "button"
            , class "btn-small"
            , onClick (onChange "")
            , disabled (not hasFilter)
            , title "Clear filter"
            , style "position" "absolute"
            , style "right" "0.25rem"
            , style "top" "50%"
            , style "transform" "translateY(-50%)"
            , style "border" "none"
            , style "background" "transparent"
            , style "font-size" "1.25rem"
            , style "cursor" (if hasFilter then "pointer" else "default")
            , style "color" (if hasFilter then "#b91c1c" else "#94a3b8")
            , style "padding" "0"
            , style "line-height" "1"
            ]
            [ text "×" ]
        ]
