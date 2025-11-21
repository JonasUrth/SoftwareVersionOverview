module Pages.Versions.New exposing (Model, Msg, page)

import Api.Data exposing (ReleaseStatus(..), Software, SoftwareType(..), Version, VersionDetail, createVersionEncoder, releaseStatusFromString, versionDecoder, versionDetailDecoder)
import Api.Endpoint as Endpoint
import Dict
import Effect exposing (Effect)
import Gen.Params.Versions.New exposing (Params)
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
        { init = init shared
        , update = update req
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    { form : Form.Model
    , error : Maybe String
    , historyError : Maybe String
    , loading : Bool
    , token : Maybe String
    }


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { form =
            { version = ""
            , softwareId = 0
            , releaseDate = "2025-11-20"
            , releaseTime = ""
            , releaseStatus = PreRelease
            , selectedCustomers = []
            , notes = [ { note = "", customerIds = [], id = Nothing } ]
            , countryFilter = ""
            , customerFilter = ""
            , versions = []
            , versionsLoading = True
            , versionDetails = Dict.empty
            , loadingVersionDetailIds = []
            }
      , error = Nothing
      , historyError = Nothing
      , loading = False
      , token = shared.token
      }
    , Effect.batch
        [ if List.isEmpty shared.software then
            Effect.fromShared Shared.RefreshSoftware

          else
            Effect.none
        , if List.isEmpty shared.customers then
            Effect.fromShared Shared.RefreshCustomers

          else
            Effect.none
        , Effect.fromCmd (Task.perform GotCurrentTime Time.now)
        , Effect.fromCmd (fetchVersions shared.token)
        ]
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
    | NoteChanged Int String
    | ToggleNoteCustomer Int Int
    | AddNote
    | RemoveNote Int
    | FormSubmitted
    | VersionCreated (Result Http.Error String)
    | VersionsFetched (Result Http.Error (List Version))
    | VersionDetailFetched Int (Result Http.Error VersionDetail)
    | GotCurrentTime Posix
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
                    Form.ensureVersionDetails updatedForm (\vid -> Effect.fromCmd (fetchVersionDetail model.token vid))
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
            in
            ( { model | form = { form | releaseStatus = releaseStatusFromString status } }, Effect.none )

        ToggleCustomer customerId ->
            let
                form = model.form
                newSelected =
                    if List.member customerId form.selectedCustomers then
                        List.filter (\id -> id /= customerId) form.selectedCustomers

                    else
                        customerId :: form.selectedCustomers
            in
            ( { model | form = { form | selectedCustomers = newSelected } }, Effect.none )

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
            in
            ( { model | form = { form | selectedCustomers = newSelected } }, Effect.none )

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

        VersionsFetched (Ok versions) ->
            let
                form = model.form
                updatedForm =
                    { form | versions = versions, versionsLoading = False }

                ( finalForm, ensureEffect ) =
                    Form.ensureVersionDetails updatedForm (\vid -> Effect.fromCmd (fetchVersionDetail model.token vid))
            in
            ( { model | form = finalForm, historyError = Nothing }, ensureEffect )

        VersionsFetched (Err _) ->
            let
                form = model.form
            in
            ( { model | form = { form | versionsLoading = False }, historyError = Just "Failed to load previous releases" }, Effect.none )

        VersionDetailFetched versionId (Ok detail) ->
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

        VersionDetailFetched versionId (Err _) ->
            let
                form = model.form
            in
            ( { model
                | historyError = Just "Failed to load some release details"
                , form = { form | loadingVersionDetailIds = List.filter ((/=) versionId) form.loadingVersionDetailIds }
              }
            , Effect.none
            )

        GotCurrentTime posix ->
            let
                form = model.form
            in
            if String.isEmpty form.releaseTime then
                ( { model | form = { form | releaseTime = posixToTimeString posix } }, Effect.none )

            else
                ( model, Effect.none )

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
                request =
                    { version = model.form.version
                    , softwareId = model.form.softwareId
                    , releaseDate = releaseDateTimeString model.form
                    , releaseStatus = model.form.releaseStatus
                    , customerIds = model.form.selectedCustomers
                    , notes =
                        List.map
                            (\n -> { note = n.note, customerIds = n.customerIds })
                            model.form.notes
                    , preReleaseBy = Nothing
                    , preReleaseDate = Nothing
                    , releasedBy = Nothing
                    , releasedDate = Nothing
                    , productionReadyBy = Nothing
                    , productionReadyDate = Nothing
                    }
            in
            ( { model | loading = True, error = Nothing }
            , Effect.fromCmd <|
                Http.request
                    { method = "POST"
                    , headers = authHeaders model.token
                    , url = Endpoint.versions []
                    , body = Http.jsonBody (createVersionEncoder request)
                    , expect = Http.expectString VersionCreated
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        VersionCreated (Ok _) ->
            ( model
            , Effect.fromCmd (Request.pushRoute Route.Versions req)
            )

        VersionCreated (Err _) ->
            ( { model | error = Just "Failed to create release", loading = False }, Effect.none )

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
    { title = "Create Release - BM Release Manager"
    , body =
        [ div [ class "container" ]
            [ div [ class "header" ]
                [ h1 [] [ text "Create Release" ]
                , button [ class "btn-secondary", onClick GoBack, type_ "button" ] [ text "← Back" ]
                ]
            , viewError model.error
            , Html.form [ onSubmit FormSubmitted, class "form-card" ]
                [ viewVersionInfo shared model.form hasSoftware
                , viewCustomerSelection shared model hasSoftware individualEnabled
                , viewNotes shared model hasSoftware
                , div [ class "form-actions" ]
                    [ button [ type_ "button", class "btn-secondary", onClick GoBack ] [ text "Cancel" ]
                    , button [ type_ "submit", class "btn-primary", disabled (model.loading || not hasSoftware) ]
                        [ text
                            (if model.loading then
                                "Creating..."

                             else if not hasSoftware then
                                "Select a software"

                             else
                                "Create Release"
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


viewVersionInfo : Shared.Model -> Form.Model -> Bool -> Html Msg
viewVersionInfo shared form fieldsEnabled =
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
                ]
                []
            ]
        , div [ class "form-group" ]
            [ label [] [ text "Software" ]
            , select [ onInput SoftwareChanged, required True ]
                (option [ value "0" ] [ text "-- Select Software --" ]
                    :: List.map
                        (\sw ->
                            option [ value (String.fromInt sw.id), selected (sw.id == form.softwareId) ]
                                [ text sw.name ]
                        )
                        shared.software
                )
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


viewCustomerList : Form.Model -> List Api.Data.Customer -> Bool -> Html Msg
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


viewCustomerCheckbox : Form.Model -> Bool -> Api.Data.Customer -> Html Msg
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


authHeaders : Maybe String -> List Http.Header
authHeaders token =
    case token of
        Just t ->
            [ Http.header "Authorization" ("Basic " ++ t) ]

        Nothing ->
            []


viewHistoryError : Maybe String -> Html Msg
viewHistoryError historyError =
    case historyError of
        Just err ->
            div [ class "help-text warning" ] [ text err ]

        Nothing ->
            text ""


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


fetchVersionDetail : Maybe String -> Int -> Cmd Msg
fetchVersionDetail token versionId =
    Http.request
        { method = "GET"
        , headers = authHeaders token
        , url = Endpoint.versions [ String.fromInt versionId ]
        , body = Http.emptyBody
        , expect = Http.expectJson (VersionDetailFetched versionId) versionDetailDecoder
        , timeout = Nothing
        , tracker = Nothing
        }




selectedSoftware : Shared.Model -> Form.Model -> Maybe Software
selectedSoftware shared form =
    shared.software
        |> List.filter (\sw -> sw.id == form.softwareId)
        |> List.head


posixToTimeString : Posix -> String
posixToTimeString posix =
    let
        hour =
            Time.toHour Time.utc posix

        minute =
            Time.toMinute Time.utc posix
    in
    padTimePart hour ++ ":" ++ padTimePart minute


padTimePart : Int -> String
padTimePart value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


releaseDateTimeString : Form.Model -> String
releaseDateTimeString form =
    let
        timePart =
            if String.isEmpty form.releaseTime then
                "00:00"

            else
                form.releaseTime
    in
    form.releaseDate ++ "T" ++ timePart ++ ":00"
