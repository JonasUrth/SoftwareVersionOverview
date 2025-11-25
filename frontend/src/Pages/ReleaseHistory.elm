module Pages.ReleaseHistory exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (CustomerDetail, CustomerReleaseStage(..), NoteDetail, ReleaseStatus(..), Software, Version, VersionDetail, releaseStatusFromString, releaseStatusLabel, releaseStatusToString, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.ReleaseHistory exposing (Params)
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


type alias VersionInfo =
    { version : String
    , isFromCurrentDate : Bool
    }


type alias ReleaseInsightRow =
    { releaseDate : String
    , releasedBy : String
    , releasedFor : String
    , notes : String
    , releaseStatuses : List ReleaseStatus
    , softwareVersions : Dict Int VersionInfo
    }


type SortColumn
    = SortDate
    | SortSoftware Int
    | SortReleasedBy
    | SortReleasedFor
    | SortNotes
    | SortStatus


type SortDirection
    = Ascending
    | Descending


type alias Model =
    { versions : List Version
    , versionDetails : Dict Int VersionDetail
    , loading : Bool
    , error : Maybe String
    , softwareList : List Software
    , compactView : Bool
    , filterDate : String
    , filterReleasedBy : String
    , filterReleasedFor : String
    , filterNotes : String
    , filterStatus : String
    , filterSoftwareVersions : Dict Int String
    , sortColumn : Maybe SortColumn
    , sortDirection : SortDirection
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , versionDetails = Dict.empty
      , loading = True
      , error = Nothing
      , softwareList = shared.software
      , compactView = True
      , filterDate = ""
      , filterReleasedBy = ""
      , filterReleasedFor = ""
      , filterNotes = ""
      , filterStatus = ""
      , filterSoftwareVersions = Dict.empty
      , sortColumn = Just SortDate
      , sortDirection = Descending
      }
    , Effect.batch
        [ fetchVersions
        , if List.isEmpty shared.software then
            Effect.fromShared Shared.RefreshSoftware

          else
            Effect.none
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
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())
    | ToggleCompactView
    | FilterDateChanged String
    | FilterReleasedByChanged String
    | FilterReleasedForChanged String
    | FilterNotesChanged String
    | FilterStatusChanged String
    | FilterSoftwareVersionChanged Int String
    | SortColumnClicked SortColumn


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotVersions (Ok versions) ->
            let
                versionIdsToFetch =
                    versions
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
            let
                updatedDetails =
                    Dict.insert versionId detail model.versionDetails

                allFetched =
                    List.length model.versions == Dict.size updatedDetails
            in
            ( { model | versionDetails = updatedDetails, loading = not allFetched }
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
            ( model
            , Effect.batch
                [ Effect.fromShared Shared.UserLoggedOut
                , Effect.fromCmd (Request.pushRoute Route.Login req)
                ]
            )

        ToggleCompactView ->
            ( { model | compactView = not model.compactView }, Effect.none )

        FilterDateChanged value ->
            ( { model | filterDate = value }, Effect.none )

        FilterReleasedByChanged value ->
            ( { model | filterReleasedBy = value }, Effect.none )

        FilterReleasedForChanged value ->
            ( { model | filterReleasedFor = value }, Effect.none )

        FilterNotesChanged value ->
            ( { model | filterNotes = value }, Effect.none )

        FilterStatusChanged value ->
            ( { model | filterStatus = value }, Effect.none )

        FilterSoftwareVersionChanged softwareId value ->
            ( { model | filterSoftwareVersions = Dict.insert softwareId value model.filterSoftwareVersions }, Effect.none )

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
        , pageTitle = "Release History - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Release History" ]
                , p [ class "subtitle" ] [ text "Complete list of all releases with history notes and customers" ]
                , label [ style "display" "flex", style "align-items" "center", style "gap" "8px", style "margin-top" "12px" ]
                    [ input
                        [ type_ "checkbox"
                        , checked model.compactView
                        , onClick ToggleCompactView
                        , style "cursor" "pointer"
                        ]
                        []
                    , text "Compact view (group by date and customer)"
                    ]
                ]
            , div [ class "full-width-content" ]
                [ viewContent shared model
                ]
            ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewContent : Shared.Model -> Model -> Html Msg
viewContent shared model =
    if model.loading then
        div [ class "loading" ] [ text "Loading releases..." ]

    else
        case model.error of
            Just err ->
                div [ class "error" ] [ text err ]

            Nothing ->
                let
                    softwareList =
                        if List.isEmpty model.softwareList then
                            shared.software

                        else
                            model.softwareList

                    rows =
                        buildReleaseInsightRows model.versions model.versionDetails
                            |> (if model.compactView then
                                    \rs -> rs |> compactRows |> fillMissingVersions softwareList

                                else
                                    identity
                               )
                            |> filterRows model softwareList
                            |> sortRows model softwareList
                in
                if List.isEmpty rows then
                    p [ class "empty" ] [ text "No releases found." ]

                else
                    viewReleaseTable model softwareList rows


buildReleaseInsightRows : List Version -> Dict Int VersionDetail -> List ReleaseInsightRow
buildReleaseInsightRows versions versionDetails =
    versions
        |> List.filterMap
            (\version ->
                Dict.get version.id versionDetails
                    |> Maybe.map
                        (\detail ->
                            let
                                rows =
                                    if List.isEmpty detail.customers then
                                        -- If no customers, create one row with empty customer
                                        [ { releaseDate = formatDate detail.releaseDate
                                          , releasedBy = detail.releasedByName
                                          , releasedFor = ""
                                          , notes = formatNotesWithSoftware detail.softwareName detail.notes
                                          , releaseStatuses = [ detail.releaseStatus ]
                                          , softwareVersions = Dict.singleton detail.softwareId { version = detail.version, isFromCurrentDate = True }
                                          }
                                        ]

                                    else
                                        -- Create one row per customer with per-customer status
                                        List.map
                                            (\customer ->
                                                { releaseDate = formatDate detail.releaseDate
                                                , releasedBy = detail.releasedByName
                                                , releasedFor = customer.name
                                                , notes = formatNotesForCustomerWithSoftware detail.softwareName customer.id detail.notes
                                                , releaseStatuses = [ customerStageToReleaseStatus customer.releaseStage ]
                                                , softwareVersions = Dict.singleton detail.softwareId { version = detail.version, isFromCurrentDate = True }
                                                }
                                            )
                                            detail.customers
                            in
                            rows
                        )
            )
        |> List.concat


formatNotesWithSoftware : String -> List NoteDetail -> String
formatNotesWithSoftware softwareName notes =
    if List.isEmpty notes then
        ""

    else
        let
            noteText =
                notes
                    |> List.map .note
                    |> String.join "\n"
        in
        "--- " ++ softwareName ++ " ---\n" ++ noteText


formatNotesForCustomerWithSoftware : String -> Int -> List NoteDetail -> String
formatNotesForCustomerWithSoftware softwareName customerId notes =
    let
        customerNotes =
            notes
                |> List.filter (\note -> List.any (\c -> c.id == customerId) note.customers)
    in
    if List.isEmpty customerNotes then
        ""

    else
        let
            noteText =
                customerNotes
                    |> List.map .note
                    |> String.join "\n"
        in
        "--- " ++ softwareName ++ " ---\n" ++ noteText


formatDate : String -> String
formatDate dateString =
    dateString
        |> String.split "T"
        |> List.head
        |> Maybe.withDefault dateString


compactRows : List ReleaseInsightRow -> List ReleaseInsightRow
compactRows rows =
    rows
        |> List.foldl
            (\row acc ->
                let
                    key =
                        ( row.releaseDate, row.releasedFor )

                    existing =
                        Dict.get key acc
                in
                case existing of
                    Just existingRow ->
                        Dict.insert key
                            { releaseDate = row.releaseDate
                            , releasedBy = combineUsers existingRow.releasedBy row.releasedBy
                            , releasedFor = row.releasedFor
                            , notes = combineNotes existingRow.notes row.notes
                            , releaseStatuses = combineStatuses existingRow.releaseStatuses row.releaseStatuses
                            , softwareVersions = combineSoftwareVersions existingRow.softwareVersions row.softwareVersions
                            }
                            acc

                    Nothing ->
                        Dict.insert key row acc
            )
            Dict.empty
        |> Dict.values


combineSoftwareVersions : Dict Int VersionInfo -> Dict Int VersionInfo -> Dict Int VersionInfo
combineSoftwareVersions dict1 dict2 =
    Dict.merge
        (\key val acc -> Dict.insert key val acc)
        (\key val1 val2 acc ->
            if val1.version == val2.version then
                Dict.insert key { version = val1.version, isFromCurrentDate = val1.isFromCurrentDate || val2.isFromCurrentDate } acc

            else
                Dict.insert key { version = val1.version ++ " / " ++ val2.version, isFromCurrentDate = val1.isFromCurrentDate || val2.isFromCurrentDate } acc
        )
        (\key val acc -> Dict.insert key val acc)
        dict1
        dict2
        Dict.empty


combineUsers : String -> String -> String
combineUsers user1 user2 =
    let
        splitUsers str =
            str
                |> String.split " / "
                |> List.concatMap (String.split "/")
                |> List.map String.trim
                |> List.filter (\u -> u /= "")

        allUsers =
            (splitUsers user1 ++ splitUsers user2)
                |> unique
                |> List.sort
    in
    String.join " / " allUsers


unique : List a -> List a
unique list =
    List.foldl
        (\item acc ->
            if List.member item acc then
                acc

            else
                item :: acc
        )
        []
        list
        |> List.reverse


combineNotes : String -> String -> String
combineNotes notes1 notes2 =
    if notes1 == "" then
        notes2

    else if notes2 == "" then
        notes1

    else
        notes1 ++ "\n\n" ++ notes2


combineStatuses : List ReleaseStatus -> List ReleaseStatus -> List ReleaseStatus
combineStatuses statuses1 statuses2 =
    statuses1 ++ statuses2
        |> List.map releaseStatusToString
        |> unique
        |> List.map releaseStatusFromString


customerStageToReleaseStatus : CustomerReleaseStage -> ReleaseStatus
customerStageToReleaseStatus stage =
    case stage of
        CustomerPreRelease ->
            PreRelease

        CustomerReleased ->
            Released

        CustomerProductionReady ->
            ProductionReady


fillMissingVersions : List Software -> List ReleaseInsightRow -> List ReleaseInsightRow
fillMissingVersions softwareList rows =
    let
        sortedRows =
            List.sortBy .releaseDate rows

        fillRowForCustomer : String -> List ReleaseInsightRow -> ReleaseInsightRow -> ReleaseInsightRow
        fillRowForCustomer customerName previousRows currentRow =
            let
                customerRows =
                    previousRows
                        |> List.filter (\r -> r.releasedFor == customerName)

                fillVersion : Int -> VersionInfo
                fillVersion softwareId =
                    case Dict.get softwareId currentRow.softwareVersions of
                        Just info ->
                            info

                        Nothing ->
                            -- Find newest earlier version for this customer/software
                            customerRows
                                |> List.reverse
                                |> List.filterMap
                                    (\prevRow ->
                                        Dict.get softwareId prevRow.softwareVersions
                                    )
                                |> List.head
                                |> Maybe.map (\info -> { info | isFromCurrentDate = False })
                                |> Maybe.withDefault { version = "", isFromCurrentDate = False }
            in
            { currentRow
                | softwareVersions =
                    softwareList
                        |> List.map (\sw -> ( sw.id, fillVersion sw.id ))
                        |> List.filter (\( _, info ) -> info.version /= "")
                        |> Dict.fromList
                        |> Dict.union currentRow.softwareVersions
            }
    in
    sortedRows
        |> List.indexedMap
            (\index row ->
                let
                    previousRows =
                        List.take index sortedRows
                in
                fillRowForCustomer row.releasedFor previousRows row
            )


sortRows : Model -> List Software -> List ReleaseInsightRow -> List ReleaseInsightRow
sortRows model softwareList rows =
    case model.sortColumn of
        Just column ->
            let
                compareRows row1 row2 =
                    case column of
                        SortDate ->
                            -- Sort by date first, then customer (case-insensitive)
                            case compare row1.releaseDate row2.releaseDate of
                                LT -> LT
                                GT -> GT
                                EQ -> compare (String.toLower row1.releasedFor) (String.toLower row2.releasedFor)

                        SortSoftware softwareId ->
                            -- Sort by software version first (case-insensitive), then date
                            let
                                version1 =
                                    Dict.get softwareId row1.softwareVersions
                                        |> Maybe.map .version
                                        |> Maybe.withDefault ""
                                        |> String.toLower

                                version2 =
                                    Dict.get softwareId row2.softwareVersions
                                        |> Maybe.map .version
                                        |> Maybe.withDefault ""
                                        |> String.toLower
                            in
                            case compare version1 version2 of
                                LT -> LT
                                GT -> GT
                                EQ -> compare row1.releaseDate row2.releaseDate

                        SortReleasedBy ->
                            -- Sort by released by first (case-insensitive), then date
                            case compare (String.toLower row1.releasedBy) (String.toLower row2.releasedBy) of
                                LT -> LT
                                GT -> GT
                                EQ -> compare row1.releaseDate row2.releaseDate

                        SortReleasedFor ->
                            -- Sort by released for first (case-insensitive), then date
                            case compare (String.toLower row1.releasedFor) (String.toLower row2.releasedFor) of
                                LT -> LT
                                GT -> GT
                                EQ -> compare row1.releaseDate row2.releaseDate

                        SortNotes ->
                            -- Sort by notes first (case-insensitive), then date
                            case compare (String.toLower row1.notes) (String.toLower row2.notes) of
                                LT -> LT
                                GT -> GT
                                EQ -> compare row1.releaseDate row2.releaseDate

                        SortStatus ->
                            -- Sort by status first (case-insensitive), then date
                            let
                                status1 =
                                    row1.releaseStatuses
                                        |> List.map releaseStatusLabel
                                        |> String.join ", "
                                        |> String.toLower

                                status2 =
                                    row2.releaseStatuses
                                        |> List.map releaseStatusLabel
                                        |> String.join ", "
                                        |> String.toLower
                            in
                            case compare status1 status2 of
                                LT -> LT
                                GT -> GT
                                EQ -> compare row1.releaseDate row2.releaseDate

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


filterRows : Model -> List Software -> List ReleaseInsightRow -> List ReleaseInsightRow
filterRows model softwareList rows =
    rows
        |> List.filter
            (\row ->
                let
                    dateMatch =
                        String.isEmpty model.filterDate
                            || String.contains (String.toLower model.filterDate) (String.toLower row.releaseDate)

                    releasedByMatch =
                        String.isEmpty model.filterReleasedBy
                            || String.contains (String.toLower model.filterReleasedBy) (String.toLower row.releasedBy)

                    releasedForMatch =
                        String.isEmpty model.filterReleasedFor
                            || String.contains (String.toLower model.filterReleasedFor) (String.toLower row.releasedFor)

                    notesMatch =
                        String.isEmpty model.filterNotes
                            || String.contains (String.toLower model.filterNotes) (String.toLower row.notes)

                    statusMatch =
                        String.isEmpty model.filterStatus
                            || List.any
                                (\status ->
                                    String.contains (String.toLower model.filterStatus) (String.toLower (releaseStatusLabel status))
                                )
                                row.releaseStatuses

                    softwareVersionsMatch =
                        softwareList
                            |> List.all
                                (\sw ->
                                    let
                                        filterValue =
                                            Dict.get sw.id model.filterSoftwareVersions
                                                |> Maybe.withDefault ""

                                        versionInfo =
                                            Dict.get sw.id row.softwareVersions
                                                |> Maybe.withDefault { version = "", isFromCurrentDate = False }
                                    in
                                    String.isEmpty filterValue
                                        || String.contains (String.toLower filterValue) (String.toLower versionInfo.version)
                                )
                in
                dateMatch && releasedByMatch && releasedForMatch && notesMatch && statusMatch && softwareVersionsMatch
            )


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
    input
        [ type_ "text"
        , placeholder "Filter..."
        , value value_
        , onInput onChange
        , style "width" "100%"
        , style "padding" "4px"
        , style "box-sizing" "border-box"
        ]
        []


viewReleaseTable : Model -> List Software -> List ReleaseInsightRow -> Html Msg
viewReleaseTable model softwareList rows =
    div [ class "table-container table-container-fullwidth", style "overflow-x" "auto" ]
        [ table [ class "release-insight-table" ]
            [ thead []
                [ tr []
                    ([ viewSortableHeader model SortDate "Release Date" []
                     ]
                        ++ List.map
                            (\sw ->
                                viewSortableHeader model (SortSoftware sw.id) sw.name [ class "software-col" ]
                            )
                            softwareList
                        ++ [ viewSortableHeader model SortReleasedBy "Released By" []
                           , viewSortableHeader model SortReleasedFor "Released For" []
                           , viewSortableHeader model SortNotes "Notes" [ class "notes-col" ]
                           , viewSortableHeader model SortStatus "Release Status" []
                           ]
                    )
                , tr [ class "filter-row" ]
                    ([ viewFilterInputCell model SortDate [] (filterInput model.filterDate FilterDateChanged)
                     ]
                        ++ List.map
                            (\sw ->
                                viewFilterInputCell model (SortSoftware sw.id) [ class "software-col" ]
                                    (filterInput (Dict.get sw.id model.filterSoftwareVersions |> Maybe.withDefault "") (FilterSoftwareVersionChanged sw.id))
                            )
                            softwareList
                        ++ [ viewFilterInputCell model SortReleasedBy [] (filterInput model.filterReleasedBy FilterReleasedByChanged)
                           , viewFilterInputCell model SortReleasedFor [] (filterInput model.filterReleasedFor FilterReleasedForChanged)
                           , viewFilterInputCell model SortNotes [ class "notes-col" ] (filterInput model.filterNotes FilterNotesChanged)
                           , viewFilterInputCell model SortStatus [] (filterInput model.filterStatus FilterStatusChanged)
                           ]
                    )
                ]
            , tbody [] (List.map (viewReleaseRow softwareList) rows)
            ]
        ]


viewReleaseRow : List Software -> ReleaseInsightRow -> Html Msg
viewReleaseRow softwareList row =
    tr []
        ([ td [] [ text row.releaseDate ]
         ]
            ++ List.map
                (\sw ->
                    let
                        versionInfo =
                            Dict.get sw.id row.softwareVersions
                                |> Maybe.withDefault { version = "", isFromCurrentDate = False }

                        styles =
                            if versionInfo.isFromCurrentDate then
                                [ style "font-weight" "bold" ]

                            else
                                [ style "color" "#888", style "font-weight" "normal" ]
                    in
                    td [ class "software-col" ]
                        [ span styles
                            [ text versionInfo.version ]
                        ]
                )
                softwareList
            ++ [ td [] [ text row.releasedBy ]
               , td [] [ text row.releasedFor ]
               , td [ class "notes-col", style "white-space" "pre-wrap" ] [ text row.notes ]
               , td []
                    (List.map
                        (\status ->
                            span [ class ("badge " ++ statusClass status), style "margin-right" "4px" ]
                                [ text (releaseStatusLabel status) ]
                        )
                        row.releaseStatuses
                    )
               ]
        )


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
