module Pages.Firmware exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (Country, CustomerReleaseStage(..), Software, SoftwareType(..), Version, VersionDetail, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.Firmware exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
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
    = SortCountry
    | SortSoftware Int
    | SortReleasedBy
    | SortNotes


type SortDirection
    = Ascending
    | Descending


type alias Model =
    { versions : List Version
    , versionDetails : Dict Int VersionDetail
    , loading : Bool
    , error : Maybe String
    , filterCountry : String
    , filterSoftwareVersions : Dict Int String
    , filterReleasedBy : String
    , filterNotes : String
    , sortColumn : Maybe SortColumn
    , sortDirection : SortDirection
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , versionDetails = Dict.empty
      , loading = True
      , error = Nothing
      , filterCountry = ""
      , filterSoftwareVersions = Dict.empty
      , filterReleasedBy = ""
      , filterNotes = ""
      , sortColumn = Nothing
      , sortDirection = Ascending
      }
    , Effect.batch
        [ if List.isEmpty shared.countries then
            Effect.fromShared Shared.RefreshCountries

          else
            Effect.none
        , if List.isEmpty shared.software then
            Effect.fromShared Shared.RefreshSoftware

          else
            Effect.none
        , if List.isEmpty shared.customers then
            Effect.fromShared Shared.RefreshCustomers

          else
            Effect.none
        , fetchVersions
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
    | NavigateToEpromHistory Int
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())
    | FilterCountryChanged String
    | FilterSoftwareVersionChanged Int String
    | FilterReleasedByChanged String
    | FilterNotesChanged String
    | SortColumnClicked SortColumn


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotVersions (Ok versions) ->
            let
                firmwareSoftwareIds =
                    shared.software
                        |> List.filter (\s -> s.type_ == Firmware)
                        |> List.map .id

                firmwareVersions =
                    versions
                        |> List.filter (\v -> List.member v.softwareId firmwareSoftwareIds)

                versionIdsToFetch =
                    firmwareVersions
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
            ( { model | versionDetails = Dict.insert versionId detail model.versionDetails }
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
            -- Even if logout API fails, clear local state and navigate to login
            ( model
            , Effect.batch
                [ Effect.fromShared Shared.UserLoggedOut
                , Effect.fromCmd (Request.pushRoute Route.Login req)
                ]
            )

        NavigateToEpromHistory countryId ->
            ( model, Effect.fromCmd (Request.pushRoute (Route.Firmware__EpromHistory__CountryId_ { countryId = String.fromInt countryId }) req) )

        FilterCountryChanged value ->
            ( { model | filterCountry = value }, Effect.none )

        FilterSoftwareVersionChanged softwareId value ->
            ( { model | filterSoftwareVersions = Dict.insert softwareId value model.filterSoftwareVersions }, Effect.none )

        FilterReleasedByChanged value ->
            ( { model | filterReleasedBy = value }, Effect.none )

        FilterNotesChanged value ->
            ( { model | filterNotes = value }, Effect.none )

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


-- VIEW


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    Layouts.Default.view
        { shared = shared
        , req = req
        , pageTitle = "Firmware Overview - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Firmware Overview" ]
                ]
            , viewContent shared model
            ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewContent : Shared.Model -> Model -> Html Msg
viewContent shared model =
    if model.loading then
        div [ class "loading" ] [ text "Loading firmware data..." ]

    else
        case model.error of
            Just err ->
                div [ class "error" ] [ text err ]

            Nothing ->
                let
                    firmwareSoftware =
                        shared.software
                            |> List.filter (\s -> s.type_ == Firmware)
                            |> List.sortBy .name

                    countries =
                        shared.countries
                            |> List.sortBy .name
                in
                if List.isEmpty shared.software && List.isEmpty shared.countries then
                    div [ class "loading" ] [ text "Loading data..." ]

                else if List.isEmpty firmwareSoftware then
                    p [ class "empty" ] 
                        [ text ("No firmware software found. " ++ 
                            (if List.isEmpty shared.software then
                                "Please ensure you are logged in and software data is loaded."
                             else
                                "Found " ++ String.fromInt (List.length shared.software) ++ " software items, but none are firmware type."
                            ))
                        ]

                else if List.isEmpty countries then
                    p [ class "empty" ] [ text "No countries found." ]

                else
                    let
                        countryRows =
                            buildCountryRows shared firmwareSoftware model countries
                                |> filterCountryRows model firmwareSoftware
                                |> sortCountryRows model firmwareSoftware
                    in
                    div [ class "table-container" ]
                        [ table [ class "firmware-table" ]
                            [ thead []
                                [ tr []
                                    ([ viewSortableHeader model SortCountry "Country" [] ]
                                        ++ List.map (\sw -> viewSortableHeader model (SortSoftware sw.id) sw.name []) firmwareSoftware
                                        ++ [ viewSortableHeader model SortReleasedBy "Released By" []
                                           , viewSortableHeader model SortNotes "Notes" []
                                           , th [] [ text "Actions" ]
                                           ]
                                    )
                                , tr [ class "filter-row" ]
                                    ([ viewFilterInputCell model SortCountry [] (filterInput model.filterCountry FilterCountryChanged) ]
                                        ++ List.map
                                            (\sw ->
                                                viewFilterInputCell model (SortSoftware sw.id) []
                                                    (filterInput (Dict.get sw.id model.filterSoftwareVersions |> Maybe.withDefault "") (FilterSoftwareVersionChanged sw.id))
                                            )
                                            firmwareSoftware
                                        ++ [ viewFilterInputCell model SortReleasedBy [] (filterInput model.filterReleasedBy FilterReleasedByChanged)
                                           , viewFilterInputCell model SortNotes [] (filterInput model.filterNotes FilterNotesChanged)
                                           , th [] []
                                           ]
                                    )
                                ]
                            , tbody []
                                (if List.isEmpty countryRows then
                                    [ tr []
                                        [ td [ colspan (4 + List.length firmwareSoftware), style "text-align" "center", style "padding" "2rem", style "color" "#64748b" ]
                                            [ text "No countries match the current filters." ]
                                        ]
                                    ]

                                 else
                                    List.map (viewCountryRowFromData firmwareSoftware) countryRows
                                )
                            ]
                        ]


viewCountryRow : Shared.Model -> List Software -> Model -> Country -> Html Msg
viewCountryRow shared firmwareSoftware model country =
    let
        countryCustomerIds =
            shared.customers
                |> List.filter (\c -> c.countryId == country.id)
                |> List.map .id

        latestVersions =
            firmwareSoftware
                |> List.map
                    (\sw ->
                        findLatestVersionForCountry sw country countryCustomerIds model
                    )

        latestReleasedBy =
            latestVersions
                |> List.filterMap identity
                |> List.sortBy (\v -> v.releaseDate)
                |> List.reverse
                |> List.head
                |> Maybe.map .releasedByName
                |> Maybe.withDefault "-"
    in
    tr []
        ([ td [] [ text country.name ] ]
            ++ List.map
                (\maybeVersion ->
                    td []
                        [ text
                            (case maybeVersion of
                                Just version ->
                                    version.version

                                Nothing ->
                                    "-"
                            )
                        ]
                )
                latestVersions
            ++ [ td [] [ text latestReleasedBy ]
               , td [] [ text (Maybe.withDefault "-" country.firmwareReleaseNote) ]
               , td [ class "actions" ]
                    [ button
                        [ class "btn-small"
                        , onClick (NavigateToEpromHistory country.id)
                        ]
                        [ text "Eprom Ver. Hist." ]
                    ]
               ]
        )


viewCountryRowFromData : List Software -> CountryRow -> Html Msg
viewCountryRowFromData firmwareSoftware row =
    tr []
        ([ td [] [ text row.country.name ] ]
            ++ List.map
                (\sw ->
                    td []
                        [ text
                            (Dict.get sw.id row.softwareVersions
                                |> Maybe.withDefault "-"
                            )
                        ]
                )
                firmwareSoftware
            ++ [ td [] [ text row.releasedBy ]
               , td [] [ text row.notes ]
               , td [ class "actions" ]
                    [ button
                        [ class "btn-small"
                        , onClick (NavigateToEpromHistory row.country.id)
                        ]
                        [ text "Eprom Ver. Hist." ]
                    ]
               ]
        )


findLatestVersionForCountry : Software -> Country -> List Int -> Model -> Maybe VersionDetail
findLatestVersionForCountry software country countryCustomerIds model =
    let
        -- Get all versions for this software
        softwareVersions =
            model.versions
                |> List.filter (\v -> v.softwareId == software.id)
                |> List.sortBy .releaseDate
                |> List.reverse

        -- Check each version detail to see if it has customers from this country
        findLatestInVersions versions =
            case versions of
                [] ->
                    Nothing

                version :: rest ->
                    case Dict.get version.id model.versionDetails of
                        Just detail ->
                            -- Check if this version has any production-ready customers from this country
                            if hasCountryProductionReadyCustomers detail countryCustomerIds then
                                Just detail

                            else
                                findLatestInVersions rest

                        Nothing ->
                            -- Version detail not loaded yet, skip
                            findLatestInVersions rest
    in
    findLatestInVersions softwareVersions


hasCountryProductionReadyCustomers : VersionDetail -> List Int -> Bool
hasCountryProductionReadyCustomers versionDetail countryCustomerIds =
    versionDetail.customers
        |> List.any
            (\customer ->
                List.member customer.id countryCustomerIds
                    && customer.releaseStage == CustomerProductionReady
            )


-- FILTER AND SORT


type alias CountryRow =
    { country : Country
    , softwareVersions : Dict Int String
    , releasedBy : String
    , notes : String
    }


buildCountryRows : Shared.Model -> List Software -> Model -> List Country -> List CountryRow
buildCountryRows shared firmwareSoftware model countries =
    countries
        |> List.map
            (\country ->
                let
                    countryCustomerIds =
                        shared.customers
                            |> List.filter (\c -> c.countryId == country.id)
                            |> List.map .id

                    latestVersions =
                        firmwareSoftware
                            |> List.map
                                (\sw ->
                                    ( sw.id
                                    , findLatestVersionForCountry sw country countryCustomerIds model
                                        |> Maybe.map .version
                                        |> Maybe.withDefault ""
                                    )
                                )
                            |> Dict.fromList

                    latestReleasedBy =
                        firmwareSoftware
                            |> List.filterMap
                                (\sw ->
                                    findLatestVersionForCountry sw country countryCustomerIds model
                                )
                            |> List.sortBy .releaseDate
                            |> List.reverse
                            |> List.head
                            |> Maybe.map .releasedByName
                            |> Maybe.withDefault "-"
                in
                { country = country
                , softwareVersions = latestVersions
                , releasedBy = latestReleasedBy
                , notes = Maybe.withDefault "-" country.firmwareReleaseNote
                }
            )


filterCountryRows : Model -> List Software -> List CountryRow -> List CountryRow
filterCountryRows model firmwareSoftware rows =
    rows
        |> List.filter
            (\row ->
                let
                    countryMatch =
                        String.isEmpty model.filterCountry
                            || String.contains (String.toLower model.filterCountry) (String.toLower row.country.name)

                    releasedByMatch =
                        String.isEmpty model.filterReleasedBy
                            || String.contains (String.toLower model.filterReleasedBy) (String.toLower row.releasedBy)

                    notesMatch =
                        String.isEmpty model.filterNotes
                            || String.contains (String.toLower model.filterNotes) (String.toLower row.notes)

                    softwareVersionsMatch =
                        firmwareSoftware
                            |> List.all
                                (\sw ->
                                    let
                                        filterValue =
                                            Dict.get sw.id model.filterSoftwareVersions
                                                |> Maybe.withDefault ""

                                        version =
                                            Dict.get sw.id row.softwareVersions
                                                |> Maybe.withDefault ""
                                    in
                                    String.isEmpty filterValue
                                        || String.contains (String.toLower filterValue) (String.toLower version)
                                )
                in
                countryMatch && releasedByMatch && notesMatch && softwareVersionsMatch
            )


sortCountryRows : Model -> List Software -> List CountryRow -> List CountryRow
sortCountryRows model firmwareSoftware rows =
    case model.sortColumn of
        Just column ->
            let
                compareRows row1 row2 =
                    case column of
                        SortCountry ->
                            compare (String.toLower row1.country.name) (String.toLower row2.country.name)

                        SortSoftware softwareId ->
                            let
                                version1 =
                                    Dict.get softwareId row1.softwareVersions
                                        |> Maybe.withDefault ""
                                        |> String.toLower

                                version2 =
                                    Dict.get softwareId row2.softwareVersions
                                        |> Maybe.withDefault ""
                                        |> String.toLower
                            in
                            compare version1 version2

                        SortReleasedBy ->
                            compare (String.toLower row1.releasedBy) (String.toLower row2.releasedBy)

                        SortNotes ->
                            compare (String.toLower row1.notes) (String.toLower row2.notes)

                sorted =
                    List.sortWith compareRows rows
            in
            case model.sortDirection of
                Ascending ->
                    sorted

                Descending ->
                    List.reverse sorted

        Nothing ->
            rows


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
