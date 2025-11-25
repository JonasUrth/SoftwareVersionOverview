module Pages.Versions.Id_ exposing (Model, Msg, page)

import Api.Data exposing (Customer, CustomerReleaseStage(..), ReleaseStatus(..), Software, SoftwareType(..), Version, VersionDetail, customerReleaseStageFromString, customerReleaseStageToString, releaseStatusFromString, updateVersionEncoder, versionDetailDecoder, versionDecoder)
import Api.Endpoint as Endpoint
import Dict
import Effect exposing (Effect)
import Gen.Params.Versions.Id_ exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onCheck, onClick, onInput, onSubmit)
import Http
import Json.Decode as Decode
import Page
import Api.VersionsForm as Form
import Request
import Shared
import Task
import Time exposing (Posix)
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update req
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    { form : Form.Model
    , versionId : Int
    , error : Maybe String
    , historyError : Maybe String
    , loading : Bool
    , token : Maybe String
    , loadingVersion : Bool
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        versionId =
            String.toInt req.params.id |> Maybe.withDefault 0
    in
    ( { form =
            { version = ""
            , softwareId = 0
            , releaseDate = ""
            , releaseTime = ""
            , releaseStatus = PreRelease
            , selectedCustomers = []
            , customerStages = Dict.empty
            , notes = []
            , countryFilter = ""
            , customerFilter = ""
            , versions = []
            , versionsLoading = False
            , versionDetails = Dict.empty
            , loadingVersionDetailIds = []
            }
      , versionId = versionId
      , error = Nothing
      , historyError = Nothing
      , loading = False
      , token = shared.token
      , loadingVersion = False
      }
    , case shared.user of
        Just _ ->
            Effect.batch
                [ if List.isEmpty shared.software then
                    Effect.fromShared Shared.RefreshSoftware

                  else
                    Effect.none
                , if List.isEmpty shared.customers then
                    Effect.fromShared Shared.RefreshCustomers

                  else
                    Effect.none
                , Effect.fromCmd (fetchVersionDetail shared.token versionId)
                , Effect.fromCmd (fetchVersions shared.token)
                ]

        Nothing ->
            Effect.none
    )



-- UPDATE


type Msg
    = VersionChanged String
    | SoftwareChanged String
    | ReleaseDateChanged String
    | ReleaseTimeChanged String
    | ReleaseStatusChanged String
    | ToggleCustomer Int
    | ToggleCountry Bool (List Int)
    | CountryFilterChanged String
    | CustomerFilterChanged String
    | CustomerStageChanged Int String
    | NoteChanged Int String
    | ToggleNoteCustomer Int Int
    | AddNote
    | RemoveNote Int
    | FormSubmitted
    | VersionUpdated (Result Http.Error String)
    | VersionDetailFetched (Result Http.Error VersionDetail)
    | VersionsFetched (Result Http.Error (List Version))
    | VersionDetailForHistoryFetched Int (Result Http.Error VersionDetail)
    | GoBack


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        VersionChanged version ->
            let
                form = model.form
            in
            ( { model | form = { form | version = version } }, Effect.none )

        SoftwareChanged softwareIdStr ->
            let
                form = model.form
                updatedForm =
                    { form | softwareId = String.toInt softwareIdStr |> Maybe.withDefault 0 }

                ( finalForm, ensureEffect ) =
                    Form.ensureVersionDetails updatedForm (\vid -> Effect.fromCmd (fetchVersionDetailForHistory model.token vid))
            in
            ( { model | form = finalForm }, ensureEffect )

        ReleaseDateChanged date ->
            let
                form = model.form
            in
            ( { model | form = { form | releaseDate = date } }, Effect.none )

        ReleaseTimeChanged timeStr ->
            let
                form = model.form
            in
            ( { model | form = { form | releaseTime = timeStr } }, Effect.none )

        ReleaseStatusChanged status ->
            let
                form = model.form
                newStatus =
                    releaseStatusFromString status

                syncedStages =
                    syncCustomerStages newStatus form.selectedCustomers form.customerStages
            in
            ( { model | form = { form | releaseStatus = newStatus, customerStages = syncedStages } }, Effect.none )

        ToggleCustomer customerId ->
            let
                form = model.form
                newSelected =
                    if List.member customerId form.selectedCustomers then
                        List.filter (\id -> id /= customerId) form.selectedCustomers

                    else
                        customerId :: form.selectedCustomers

                syncedStages =
                    syncCustomerStages form.releaseStatus newSelected form.customerStages
            in
            ( { model | form = { form | selectedCustomers = newSelected, customerStages = syncedStages } }, Effect.none )

        ToggleCountry checked customerIds ->
            let
                form = model.form
                newSelected =
                    if checked then
                        List.foldl
                            (\cid acc ->
                                if List.member cid acc then
                                    acc

                                else
                                    cid :: acc
                            )
                            form.selectedCustomers
                            customerIds

                    else
                        List.filter (\cid -> not (List.member cid customerIds)) form.selectedCustomers

                syncedStages =
                    syncCustomerStages form.releaseStatus newSelected form.customerStages
            in
            ( { model | form = { form | selectedCustomers = newSelected, customerStages = syncedStages } }, Effect.none )


        CountryFilterChanged query ->
            let
                form = model.form
            in
            ( { model | form = { form | countryFilter = query } }, Effect.none )

        CustomerFilterChanged query ->
            let
                form = model.form
            in
            ( { model | form = { form | customerFilter = query } }, Effect.none )

        CustomerStageChanged customerId stageStr ->
            let
                form = model.form
                newStage =
                    customerReleaseStageFromString stageStr
            in
            ( { model | form = { form | customerStages = Dict.insert customerId newStage form.customerStages } }, Effect.none )

        VersionsFetched (Ok versions) ->
            let
                form = model.form
                updatedForm =
                    { form | versions = versions, versionsLoading = False }

                ( finalForm, ensureEffect ) =
                    Form.ensureVersionDetails updatedForm (\vid -> Effect.fromCmd (fetchVersionDetailForHistory model.token vid))
            in
            ( { model | form = finalForm, historyError = Nothing }, ensureEffect )

        VersionsFetched (Err _) ->
            let
                form = model.form
            in
            ( { model | form = { form | versionsLoading = False }, historyError = Just "Failed to load previous releases" }, Effect.none )

        VersionDetailFetched (Ok detail) ->
            let
                ( dateStr, timeStr ) =
                    parseReleaseDateTime detail.releaseDate

                notes =
                    List.map
                        (\note ->
                            { note = note.note
                            , customerIds = List.map .id note.customers
                            , id = Just note.id
                            }
                        )
                        detail.notes
            in
            ( { model
                | form =
                    { version = detail.version
                    , softwareId = detail.softwareId
                    , releaseDate = dateStr
                    , releaseTime = timeStr
                    , releaseStatus = detail.releaseStatus
                    , selectedCustomers = List.map .id detail.customers
                    , customerStages =
                        Dict.fromList
                            (List.map
                                (\customerDetail -> ( customerDetail.id, customerDetail.releaseStage ))
                                detail.customers
                            )
                    , notes = notes
                    , countryFilter = model.form.countryFilter
                    , customerFilter = model.form.customerFilter
                    , versions = model.form.versions
                    , versionsLoading = model.form.versionsLoading
                    , versionDetails = model.form.versionDetails
                    , loadingVersionDetailIds = model.form.loadingVersionDetailIds
                    }
                , loadingVersion = False
              }
            , Effect.none
            )

        VersionDetailFetched (Err _) ->
            ( { model | error = Just "Failed to load version", loadingVersion = False }, Effect.none )

        VersionDetailForHistoryFetched versionId (Ok detail) ->
            let
                form = model.form
            in
            ( { model
                | form =
                    { form
                        | versionDetails = Dict.insert versionId detail form.versionDetails
                        , loadingVersionDetailIds = List.filter ((/=) versionId) form.loadingVersionDetailIds
                    }
              }
            , Effect.none
            )

        VersionDetailForHistoryFetched versionId (Err _) ->
            let
                form = model.form
            in
            ( { model
                | historyError = Just "Failed to load some release details"
                , form = { form | loadingVersionDetailIds = List.filter ((/=) versionId) form.loadingVersionDetailIds }
              }
            , Effect.none
            )

        NoteChanged index noteText ->
            let
                form = model.form
                updateNote i note =
                    if i == index then
                        { note | note = noteText }

                    else
                        note
            in
            ( { model | form = { form | notes = List.indexedMap updateNote form.notes } }, Effect.none )

        ToggleNoteCustomer noteIndex customerId ->
            let
                form = model.form
                updateNote i note =
                    if i == noteIndex then
                        let
                            newCustomerIds =
                                if List.member customerId note.customerIds then
                                    List.filter (\id -> id /= customerId) note.customerIds

                                else
                                    customerId :: note.customerIds
                        in
                        { note | customerIds = newCustomerIds }

                    else
                        note
            in
            ( { model | form = { form | notes = List.indexedMap updateNote form.notes } }, Effect.none )

        AddNote ->
            let
                form = model.form
            in
            ( { model | form = { form | notes = form.notes ++ [ { note = "", customerIds = [], id = Nothing } ] } }, Effect.none )

        RemoveNote index ->
            let
                form = model.form
            in
            ( { model | form = { form | notes = List.take index form.notes ++ List.drop (index + 1) form.notes } }, Effect.none )

        FormSubmitted ->
            let
                releaseDateTime =
                    if String.isEmpty model.form.releaseTime then
                        model.form.releaseDate ++ "T00:00:00"

                    else
                        model.form.releaseDate ++ "T" ++ model.form.releaseTime ++ ":00"

                request =
                    { id = model.versionId
                    , releaseDate = releaseDateTime
                    , releaseStatus = model.form.releaseStatus
                    , customerIds = model.form.selectedCustomers
                    , customerStages = buildCustomerStagePayload model.form
                    , notes =
                        List.map
                            (\n -> { id = n.id, note = n.note, customerIds = n.customerIds })
                            model.form.notes
                    }
            in
            ( { model | loading = True, error = Nothing }
            , Effect.fromCmd <|
                Http.request
                    { method = "PUT"
                    , headers = authHeaders model.token
                    , url = Endpoint.versions [ String.fromInt model.versionId ]
                    , body = Http.jsonBody (updateVersionEncoder request)
                    , expect = Http.expectString VersionUpdated
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        VersionUpdated (Ok _) ->
            ( model
            , Effect.fromCmd (Request.pushRoute Route.Versions req)
            )

        VersionUpdated (Err _) ->
            ( { model | error = Just "Failed to update release", loading = False }, Effect.none )

        GoBack ->
            ( model, Effect.fromCmd (Request.pushRoute Route.Versions req) )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    let
        maybeSoftware =
            selectedSoftware shared model.form

        hasSoftware =
            Maybe.withDefault False (Maybe.map (\_ -> True) maybeSoftware)

        isWindows =
            Maybe.withDefault False
                (Maybe.map (\sw -> sw.type_ == Windows) maybeSoftware)

        individualEnabled =
            hasSoftware && isWindows
    in
    { title = "Edit Release - BM Release Manager"
    , body =
        [ div [ class "container" ]
            [ div [ class "header" ]
                [ h1 [] [ text "Edit Release" ]
                , button [ class "btn-secondary", onClick GoBack, type_ "button" ] [ text "← Back" ]
                ]
            , viewError model.error
            , if model.loadingVersion then
                div [ class "loading" ] [ text "Loading version..." ]

              else
                Html.form [ onSubmit FormSubmitted, class "form-card" ]
                    [ viewVersionInfo shared model.form hasSoftware individualEnabled
                    , viewCustomerSelection shared model hasSoftware individualEnabled
                    , viewCustomerStages shared model hasSoftware individualEnabled
                    , viewNotes shared model hasSoftware
                    , div [ class "form-actions" ]
                        [ button [ type_ "button", class "btn-secondary", onClick GoBack ] [ text "Cancel" ]
                        , button [ type_ "submit", class "btn-primary", disabled (model.loading || not hasSoftware) ]
                            [ text
                                (if model.loading then
                                    "Updating..."

                                 else if not hasSoftware then
                                    "Select a software"

                                 else
                                    "Update Release"
                                )
                            ]
                        ]
                    ]
            ]
        ]
    }


viewError : Maybe String -> Html Msg
viewError error =
    case error of
        Just err ->
            div [ class "error" ] [ text err ]

        Nothing ->
            text ""


viewVersionInfo : Shared.Model -> Form.Model -> Bool -> Bool -> Html Msg
viewVersionInfo shared form fieldsEnabled customEnabled =
    div []
        [ h3 [] [ text "Release Information" ]
        , div [ class "form-group" ]
            [ label [] [ text "Version Number" ]
            , input
                [ type_ "text"
                , value form.version
                , onInput VersionChanged
                , placeholder "e.g., 1.0.0"
                , required True
                , disabled True
                ]
                []
            , p [ class "help-text" ] [ text "Version number cannot be changed" ]
            ]
        , div [ class "form-group" ]
            [ label [] [ text "Software" ]
            , select [ onInput SoftwareChanged, required True, disabled True ]
                (option [ value "0" ] [ text "-- Select Software --" ]
                    :: List.map
                        (\sw ->
                            option [ value (String.fromInt sw.id), selected (sw.id == form.softwareId) ]
                                [ text sw.name ]
                        )
                        shared.software
                )
            , p [ class "help-text" ] [ text "Software cannot be changed" ]
            ]
        , div [ class "form-group" ]
            [ label [] [ text "Release Date" ]
            , input
                [ type_ "date"
                , value form.releaseDate
                , onInput ReleaseDateChanged
                , required True
                , disabled (not fieldsEnabled)
                ]
                []
            ]
        , div [ class "form-group" ]
            [ label [] [ text "Release Time" ]
            , input
                [ type_ "time"
                , value form.releaseTime
                , onInput ReleaseTimeChanged
                , required True
                , disabled (not fieldsEnabled)
                ]
                []
            ]
        , div [ class "form-group" ]
            [ label [] [ text "Release Status" ]
            , select [ onInput ReleaseStatusChanged, required True, disabled (not fieldsEnabled) ]
                [ option [ value "PreRelease", selected (form.releaseStatus == PreRelease) ] [ text "Pre-Release" ]
                , option [ value "Released", selected (form.releaseStatus == Released) ] [ text "Released" ]
                , option [ value "ProductionReady", selected (form.releaseStatus == ProductionReady) ] [ text "Production Ready" ]
                , option
                    [ value "CustomPerCustomer"
                    , selected (form.releaseStatus == CustomPerCustomer)
                    , disabled (not customEnabled)
                    ]
                    [ text "Individual customer releases" ]
                ]
            ]
        ]


viewCustomerSelection : Shared.Model -> Model -> Bool -> Bool -> Html Msg
viewCustomerSelection shared model countriesEnabled individualsEnabled =
    let
        countries =
            Form.countryGroups shared.customers
    in
    div []
        [ h3 [] [ text "Select Customers" ]
        , viewHistoryError model.historyError
        , p [] [ text ("Selected: " ++ String.fromInt (List.length model.form.selectedCustomers) ++ " customer(s)") ]
        , div
            [ class "selection-sections"
            , style "display" "flex"
            , style "gap" "2rem"
            , style "align-items" "flex-start"
            , style "flex-wrap" "wrap"
            ]
            [ viewCountrySelection model.form countries countriesEnabled
            , viewCustomerList model.form shared.customers individualsEnabled
            ]
        ]


viewCustomerStages : Shared.Model -> Model -> Bool -> Bool -> Html Msg
viewCustomerStages shared model hasSoftware individualsEnabled =
    if (not hasSoftware) || model.form.releaseStatus /= CustomPerCustomer then
        text ""

    else
        let
            selectedCustomers =
                shared.customers
                    |> List.filter (\customer -> List.member customer.id model.form.selectedCustomers)
                    |> List.sortBy .name
        in
        div []
            [ h3 [] [ text "Customer Release Stages" ]
            , if not individualsEnabled then
                p [ class "help-text warning" ]
                    [ text "Individual customer releases are available only for Windows software." ]

              else if List.isEmpty selectedCustomers then
                p [ class "help-text" ] [ text "Select at least one customer to configure stages." ]

              else
                div [ class "customer-stages" ]
                    (List.map (viewCustomerStageControl model) selectedCustomers)
            ]


viewCustomerStageControl : Model -> Customer -> Html Msg
viewCustomerStageControl model customer =
    let
        stage =
            Dict.get customer.id model.form.customerStages
                |> Maybe.withDefault CustomerPreRelease

        stageValue =
            customerReleaseStageToString stage
    in
    div [ class "customer-stage-row" ]
        [ div [] [ strong [] [ text customer.name ], text (" (" ++ customer.country.name ++ ")") ]
        , select
            [ value stageValue
            , onInput (CustomerStageChanged customer.id)
            ]
            (List.map (viewStageOption stageValue) customerStageOptions)
        ]


viewStageOption : String -> CustomerReleaseStage -> Html Msg
viewStageOption selectedValue stage =
    let
        stageValue =
            customerReleaseStageToString stage
    in
    option
        [ value stageValue
        , selected (selectedValue == stageValue)
        ]
        [ text (customerStageLabel stage) ]


viewCountrySelection : Form.Model -> List Form.CountryGroup -> Bool -> Html Msg
viewCountrySelection form countries enabled =
    let
        filtered =
            Form.filterCountryGroups form.countryFilter form countries
    in
    div [ class "country-selection", style "flex" "1" ]
        [ h4 [] [ text "By Country" ]
        , input
            [ type_ "text"
            , placeholder "Search countries..."
            , value form.countryFilter
            , onInput CountryFilterChanged
            , disabled (not enabled)
            ]
            []
        , div [ class "customer-checkboxes" ]
            (List.map (viewCountryCheckbox form enabled) filtered)
        ]


viewCountryCheckbox : Form.Model -> Bool -> Form.CountryGroup -> Html Msg
viewCountryCheckbox form enabled country =
    let
        allSelected =
            List.all (\cid -> List.member cid form.selectedCustomers) country.customerIds
        labelText =
            Form.countryDisplayLabel form country
    in
    label [ class "checkbox-label" ]
        [ input
            [ type_ "checkbox"
            , checked allSelected
            , onCheck (\checked -> ToggleCountry checked country.customerIds)
            , disabled (not enabled)
            ]
            []
        , text (" " ++ labelText)
        ]


viewCustomerList : Form.Model -> List Customer -> Bool -> Html Msg
viewCustomerList form customers enabled =
    let
        filtered =
            Form.filterCustomers form.customerFilter customers
    in
    div [ class "customer-selection", style "flex" "1" ]
        [ h4 [] [ text "Individual Customers" ]
        , input
            [ type_ "text"
            , placeholder "Search customers..."
            , value form.customerFilter
            , onInput CustomerFilterChanged
            , disabled (not enabled)
            ]
            []
        , div [ class "customer-checkboxes" ]
            (List.map (viewCustomerCheckbox form enabled) filtered)
        ]


viewCustomerCheckbox : Form.Model -> Bool -> Customer -> Html Msg
viewCustomerCheckbox form enabled customer =
    label [ class "checkbox-label" ]
        [ input
            [ type_ "checkbox"
            , checked (List.member customer.id form.selectedCustomers)
            , onCheck (\_ -> ToggleCustomer customer.id)
            , disabled (not enabled)
            ]
            []
        , text (" " ++ customer.name ++ " (" ++ customer.country.name ++ ")")
        ]


customerStageOptions : List CustomerReleaseStage
customerStageOptions =
    [ CustomerPreRelease, CustomerReleased, CustomerProductionReady ]


customerStageLabel : CustomerReleaseStage -> String
customerStageLabel stage =
    case stage of
        CustomerPreRelease ->
            "Pre-Release"

        CustomerReleased ->
            "Released"

        CustomerProductionReady ->
            "Production Ready"


viewNotes : Shared.Model -> Model -> Bool -> Html Msg
viewNotes shared model enabled =
    div []
        [ h3 [] [ text "Release Notes" ]
        , p [ class "help-text" ] [ text "Each note must be assigned to at least one customer" ]
        , div [] (List.indexedMap (viewNoteForm shared enabled model) model.form.notes)
        , button [ type_ "button", class "btn-secondary", onClick AddNote, disabled (not enabled) ] [ text "+ Add Note" ]
        ]


viewNoteForm : Shared.Model -> Bool -> Model -> Int -> Form.NoteForm -> Html Msg
viewNoteForm shared enabled model index note =
    div [ class "note-form" ]
        [ div [ class "form-group" ]
            [ label [] [ text ("Note " ++ String.fromInt (index + 1)) ]
            , textarea
                [ value note.note
                , onInput (NoteChanged index)
                , placeholder "Release note..."
                , rows 3
                , required True
                , disabled (not enabled)
                ]
                []
            ]
        , div [ class "form-group" ]
            [ label [] [ text "Assign to customers:" ]
            , div [ class "customer-checkboxes" ]
                (List.filterMap
                    (\customer ->
                        if List.member customer.id model.form.selectedCustomers then
                            Just
                                (label [ class "checkbox-label" ]
                                    [ input
                                        [ type_ "checkbox"
                                        , checked (List.member customer.id note.customerIds)
                                        , onCheck (\_ -> ToggleNoteCustomer index customer.id)
                                        , disabled (not enabled)
                                        ]
                                        []
                                    , text (" " ++ customer.name)
                                    ]
                                )

                        else
                            Nothing
                    )
                    shared.customers
                )
            ]
        , if List.length model.form.notes > 1 then
            button [ type_ "button", class "btn-small btn-danger", onClick (RemoveNote index), disabled (not enabled) ] [ text "Remove Note" ]

          else
            text ""
        ]


viewHistoryError : Maybe String -> Html Msg
viewHistoryError historyError =
    case historyError of
        Just err ->
            div [ class "help-text warning" ] [ text err ]

        Nothing ->
            text ""


-- HELPER FUNCTIONS


authHeaders : Maybe String -> List Http.Header
authHeaders token =
    case token of
        Just t ->
            [ Http.header "Authorization" ("Basic " ++ t) ]

        Nothing ->
            []


selectedSoftware : Shared.Model -> Form.Model -> Maybe Software
selectedSoftware shared form =
    shared.software
        |> List.filter (\sw -> sw.id == form.softwareId)
        |> List.head


parseReleaseDateTime : String -> ( String, String )
parseReleaseDateTime dateTimeStr =
    case String.split "T" dateTimeStr of
        [ date, timeWithSeconds ] ->
            case String.split ":" timeWithSeconds of
                [ hour, minute, _ ] ->
                    ( date, hour ++ ":" ++ minute )

                _ ->
                    ( date, "00:00" )

        _ ->
            ( dateTimeStr, "00:00" )


fetchVersionDetail : Maybe String -> Int -> Cmd Msg
fetchVersionDetail token versionId =
    Http.request
        { method = "GET"
        , headers = authHeaders token
        , url = Endpoint.versions [ String.fromInt versionId ]
        , body = Http.emptyBody
        , expect = Http.expectJson VersionDetailFetched versionDetailDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


fetchVersionDetailForHistory : Maybe String -> Int -> Cmd Msg
fetchVersionDetailForHistory token versionId =
    Http.request
        { method = "GET"
        , headers = authHeaders token
        , url = Endpoint.versions [ String.fromInt versionId ]
        , body = Http.emptyBody
        , expect = Http.expectJson (VersionDetailForHistoryFetched versionId) versionDetailDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


fetchVersions : Maybe String -> Cmd Msg
fetchVersions token =
    Http.request
        { method = "GET"
        , headers = authHeaders token
        , url = Endpoint.versions []
        , body = Http.emptyBody
        , expect = Http.expectJson VersionsFetched (Decode.list versionDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


buildCustomerStagePayload : Form.Model -> List { customerId : Int, releaseStage : CustomerReleaseStage }
buildCustomerStagePayload form =
    let
        fallbackStage =
            defaultStageForStatus form.releaseStatus
    in
    form.selectedCustomers
        |> List.map
            (\customerId ->
                { customerId = customerId
                , releaseStage =
                    Dict.get customerId form.customerStages
                        |> Maybe.withDefault
                            (if form.releaseStatus == CustomPerCustomer then
                                CustomerPreRelease

                             else
                                fallbackStage
                            )
                }
            )


syncCustomerStages : ReleaseStatus -> List Int -> Dict.Dict Int CustomerReleaseStage -> Dict.Dict Int CustomerReleaseStage
syncCustomerStages releaseStatus selected current =
    let
        trimmed =
            Dict.filter (\cid _ -> List.member cid selected) current

        stageForStatus =
            defaultStageForStatus releaseStatus

        insertDefault cid acc =
            case Dict.get cid acc of
                Just _ ->
                    if releaseStatus == CustomPerCustomer then
                        acc

                    else
                        Dict.insert cid stageForStatus acc

                Nothing ->
                    let
                        defaultStage =
                            if releaseStatus == CustomPerCustomer then
                                CustomerPreRelease

                            else
                                stageForStatus
                    in
                    Dict.insert cid defaultStage acc
    in
    List.foldl insertDefault trimmed selected


defaultStageForStatus : ReleaseStatus -> CustomerReleaseStage
defaultStageForStatus status =
    case status of
        PreRelease ->
            CustomerPreRelease

        Released ->
            CustomerReleased

        ProductionReady ->
            CustomerProductionReady

        CustomPerCustomer ->
            CustomerPreRelease
