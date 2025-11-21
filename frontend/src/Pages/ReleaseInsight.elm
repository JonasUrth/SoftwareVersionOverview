module Pages.ReleaseInsight exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (CustomerDetail, NoteDetail, ReleaseStatus(..), Software, Version, VersionDetail, releaseStatusFromString, releaseStatusToString, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.ReleaseInsight exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, preventDefaultOn)
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


type alias Model =
    { versions : List Version
    , versionDetails : Dict Int VersionDetail
    , loading : Bool
    , error : Maybe String
    , softwareList : List Software
    , compactView : Bool
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { versions = []
      , versionDetails = Dict.empty
      , loading = True
      , error = Nothing
      , softwareList = shared.software
      , compactView = True
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
        , pageTitle = "Release Insight - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Release Insight" ]
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
                in
                if List.isEmpty rows then
                    p [ class "empty" ] [ text "No releases found." ]

                else
                    viewReleaseTable softwareList rows


buildReleaseInsightRows : List Version -> Dict Int VersionDetail -> List ReleaseInsightRow
buildReleaseInsightRows versions versionDetails =
    versions
        |> List.filterMap
            (\version ->
                Dict.get version.id versionDetails
                    |> Maybe.map
                        (\detail ->
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
                                -- Create one row per customer
                                List.map
                                    (\customer ->
                                        { releaseDate = formatDate detail.releaseDate
                                        , releasedBy = detail.releasedByName
                                        , releasedFor = customer.name
                                        , notes = formatNotesForCustomerWithSoftware detail.softwareName customer.id detail.notes
                                        , releaseStatuses = [ detail.releaseStatus ]
                                        , softwareVersions = Dict.singleton detail.softwareId { version = detail.version, isFromCurrentDate = True }
                                        }
                                    )
                                    detail.customers
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


viewReleaseTable : List Software -> List ReleaseInsightRow -> Html Msg
viewReleaseTable softwareList rows =
    div [ class "table-container table-container-fullwidth", style "overflow-x" "auto" ]
        [ table [ class "release-insight-table" ]
            [ thead []
                [ tr []
                    ([ th [] [ text "Release Date" ]
                     ]
                        ++ List.map (\sw -> th [] [ text sw.name ]) softwareList
                        ++ [ th [] [ text "Released By" ]
                           , th [] [ text "Released For" ]
                           , th [] [ text "Notes" ]
                           , th [] [ text "Release Status" ]
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
                    td []
                        [ span styles
                            [ text versionInfo.version ]
                        ]
                )
                softwareList
            ++ [ td [] [ text row.releasedBy ]
               , td [] [ text row.releasedFor ]
               , td [ style "white-space" "pre-wrap", style "max-width" "400px" ] [ text row.notes ]
               , td []
                    (List.map
                        (\status ->
                            span [ class ("badge " ++ statusClass status), style "margin-right" "4px" ]
                                [ text (releaseStatusToString status) ]
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
