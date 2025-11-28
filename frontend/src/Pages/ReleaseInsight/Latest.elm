module Pages.ReleaseInsight.Latest exposing (Model, Msg, page)

import Api.Auth
import Api.Data
    exposing
        ( Customer
        , CustomerReleaseStage(..)
        , NoteDetail
        , ReleaseStatus(..)
        , Software
        , SoftwareType(..)
        , VersionDetail
        , customerDecoder
        , releaseStatusLabel
        , softwareDecoder
        , versionDetailDecoder
        )
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.ReleaseInsight.Latest exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Layouts.Default
import Page
import Request
import Shared
import Utils.NoteFormatter
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared req
        , view = view shared req
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { windowsSoftware : List Software
    , customers : List Customer
    , selectedSoftware : Maybe Int
    , selectedCustomer : Maybe Int
    , latestRelease : Maybe VersionDetail
    , softwareLoading : Bool
    , customersLoading : Bool
    , latestLoading : Bool
    , latestError : Maybe String
    , installerState : InstallerState
    , softwareError : Maybe String
    , customersError : Maybe String
    }


type InstallerState
    = InstallerIdle
    | InstallerLaunching
    | InstallerSuccess
    | InstallerError String


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared _ =
    ( { windowsSoftware = []
      , customers = []
      , selectedSoftware = Nothing
      , selectedCustomer = Nothing
      , latestRelease = Nothing
      , softwareLoading = True
      , customersLoading = True
      , latestLoading = False
      , latestError = Nothing
      , installerState = InstallerIdle
      , softwareError = Nothing
      , customersError = Nothing
      }
    , Effect.batch
        [ fetchSoftware
        , fetchCustomers
        ]
    )



-- UPDATE


type Msg
    = GotSoftware (Result Http.Error (List Software))
    | GotCustomers (Result Http.Error (List Customer))
    | SoftwareSelected String
    | CustomerSelected String
    | GotLatestRelease (Result Http.Error VersionDetail)
    | OpenInstallerClicked
    | InstallerOpened (Result Http.Error ())
    | NavigateToRoute Route.Route
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())


update :
    Shared.Model
    -> Request.With Params
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        GotSoftware (Ok software) ->
            let
                windowsOnly =
                    software
                        |> List.filter (\sw -> sw.type_ == Windows)
                        |> List.sortBy .name
            in
            ( { model
                | windowsSoftware = windowsOnly
                , softwareLoading = False
                , softwareError = Nothing
              }
            , Effect.none
            )

        GotSoftware (Err err) ->
            ( { model
                | windowsSoftware = []
                , softwareLoading = False
                , softwareError = Just ("Unable to load software list (" ++ httpErrorToString err ++ ").")
              }
            , Effect.none
            )

        GotCustomers (Ok customers) ->
            ( { model
                | customers = customers |> List.sortBy .name
                , customersLoading = False
                , customersError = Nothing
              }
            , Effect.none
            )

        GotCustomers (Err err) ->
            ( { model
                | customers = []
                , customersLoading = False
                , customersError = Just ("Unable to load customer list (" ++ httpErrorToString err ++ ").")
              }
            , Effect.none
            )

        SoftwareSelected value ->
            let
                updatedModel =
                    case String.toInt value of
                        Just softwareId ->
                            { model
                                | selectedSoftware = Just softwareId
                                , selectedCustomer = Nothing
                                , latestRelease = Nothing
                                , latestError = Nothing
                                , installerState = InstallerIdle
                            }

                        Nothing ->
                            { model
                                | selectedSoftware = Nothing
                                , selectedCustomer = Nothing
                                , latestRelease = Nothing
                                , latestError = Nothing
                                , installerState = InstallerIdle
                            }
            in
            ( updatedModel, Effect.none )

        CustomerSelected value ->
            case String.toInt value of
                Just customerId ->
                    let
                        nextModel =
                            { model
                                | selectedCustomer = Just customerId
                                , latestRelease = Nothing
                                , latestError = Nothing
                                , installerState = InstallerIdle
                            }
                    in
                    case model.selectedSoftware of
                        Just softwareId ->
                            ( { nextModel | latestLoading = True }
                            , fetchLatestRelease softwareId customerId
                            )

                        Nothing ->
                            ( nextModel, Effect.none )

                Nothing ->
                    ( { model
                        | selectedCustomer = Nothing
                        , latestRelease = Nothing
                        , latestError = Nothing
                        , installerState = InstallerIdle
                      }
                    , Effect.none
                    )

        GotLatestRelease (Ok detail) ->
            ( { model
                | latestRelease = Just detail
                , latestLoading = False
                , latestError = Nothing
              }
            , Effect.none
            )

        GotLatestRelease (Err err) ->
            let
                friendlyError =
                    case err of
                        Http.BadStatus statusCode ->
                            if statusCode == 404 then
                                "No production-ready release is available for this software and customer."

                            else
                                httpErrorToString err

                        _ ->
                            httpErrorToString err
            in
            ( { model
                | latestRelease = Nothing
                , latestLoading = False
                , latestError = Just friendlyError
              }
            , Effect.none
            )

        OpenInstallerClicked ->
            case ( model.selectedSoftware, model.selectedCustomer, model.latestRelease ) of
                ( Just softwareId, Just customerId, Just detail ) ->
                    ( { model | installerState = InstallerLaunching }
                    , launchInstaller softwareId customerId detail.version
                    )

                _ ->
                    ( model, Effect.none )

        InstallerOpened (Ok _) ->
            ( { model | installerState = InstallerSuccess }, Effect.none )

        InstallerOpened (Err err) ->
            ( { model | installerState = InstallerError (httpErrorToString err) }, Effect.none )

        NavigateToRoute route ->
            ( model, Effect.fromCmd (Request.pushRoute route req) )

        LogoutRequested ->
            ( model, Effect.fromCmd (Api.Auth.logout LogoutResponse) )

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



-- EFFECT HELPERS


fetchSoftware : Effect Msg
fetchSoftware =
    Http.get
        { url = Endpoint.software []
        , expect = Http.expectJson GotSoftware (Decode.list softwareDecoder)
        }
        |> Effect.fromCmd


fetchCustomers : Effect Msg
fetchCustomers =
    Http.get
        { url = Endpoint.customers []
        , expect = Http.expectJson GotCustomers (Decode.list customerDecoder)
        }
        |> Effect.fromCmd


fetchLatestRelease : Int -> Int -> Effect Msg
fetchLatestRelease softwareId customerId =
    Http.get
        { url = Endpoint.versionsLatest softwareId customerId
        , expect = Http.expectJson GotLatestRelease versionDetailDecoder
        }
        |> Effect.fromCmd


launchInstaller : Int -> Int -> String -> Effect Msg
launchInstaller softwareId customerId version =
    Http.post
        { url = Endpoint.installerOpen
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "softwareId", Encode.int softwareId )
                    , ( "customerId", Encode.int customerId )
                    , ( "version", Encode.string version )
                    ]
                )
        , expect = Http.expectJson InstallerOpened (Decode.succeed ())
        }
        |> Effect.fromCmd



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
        , pageTitle = "Latest Release Insight - BM Release Manager"
        , pageBody =
            [ div [ class "header" ]
                [ h1 [] [ text "Latest Release Insight" ]
                , p [ class "subtitle" ]
                    [ text "Select a Windows software package and customer to see the most recent release details." ]
                ]
            , div [ class "card" ] [ viewSelectionForm model ]
            , div [ class "card" ] [ viewLatestReleaseSection model ]
            ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewSelectionForm : Model -> Html Msg
viewSelectionForm model =
    let
        dataErrors =
            List.filterMap identity
                [ model.softwareError
                , model.customersError
                ]
    in
    div [ class "selection-form" ]
        ([ div [ class "form-group" ]
            [ label [] [ text "1. Choose Windows software" ]
            , select
                [ onInput SoftwareSelected
                , class "form-control"
                , disabled model.softwareLoading
                ]
                (option [ value "" ] [ text "Select Windows software..." ]
                    :: List.map (viewSoftwareOption model.selectedSoftware) model.windowsSoftware
                )
            ]
         , div [ class "form-group" ]
            [ label [] [ text "2. Choose customer" ]
            , select
                [ onInput CustomerSelected
                , class "form-control"
                , disabled (model.selectedSoftware == Nothing || model.customersLoading)
                ]
                (option [ value "" ] [ text "Select customer..." ]
                    :: List.map
                        (viewCustomerOption model.selectedCustomer)
                        model.customers
                )
            , p [ class "help-text" ]
                [ text "Customers become available after a Windows software is selected." ]
            ]
         ]
            ++ (if model.softwareLoading || model.customersLoading then
                    [ div [ class "info" ] [ text "Loading data..." ] ]

                else
                    []
               )
            ++ (if List.isEmpty dataErrors then
                    []

                else
                    [ div [ class "error" ]
                        (List.map (\err -> p [] [ text err ]) dataErrors)
                    ]
               )
        )


viewSoftwareOption : Maybe Int -> Software -> Html Msg
viewSoftwareOption selectedId software =
    option
        [ value (String.fromInt software.id)
        , selected (selectedId == Just software.id)
        ]
        [ text software.name ]


viewCustomerOption : Maybe Int -> Customer -> Html Msg
viewCustomerOption selectedId customer =
    let
        labelText =
            customer.name
                ++ " - "
                ++ customer.country.name
                ++ (if customer.isActive then
                        ""

                    else
                        " (inactive)"
                   )
    in
    option
        [ value (String.fromInt customer.id)
        , selected (selectedId == Just customer.id)
        ]
        [ text labelText ]


viewLatestReleaseSection : Model -> Html Msg
viewLatestReleaseSection model =
    if model.latestLoading then
        div [ class "info" ] [ text "Loading latest release..." ]

    else
        case model.selectedSoftware of
            Nothing ->
                p [] [ text "Select a Windows software to get started." ]

            Just _ ->
                case model.selectedCustomer of
                    Nothing ->
                        p [] [ text "Now choose the customer to continue." ]

                    Just customerId ->
                        case model.latestRelease of
                            Just detail ->
                                let
                                    customerStage =
                                        releaseStageForCustomer detail customerId

                                    isProductionReady =
                                        customerStage == CustomerProductionReady

                                    statusLabel =
                                        releaseStatusLabel (releaseStatusFromStage customerStage)
                                in
                                div [ class "latest-release" ]
                                    [ h2 [] [ text detail.softwareName ]
                                    , div [ class "release-summary" ]
                                        [ p []
                                            [ strong [] [ text "Version: " ]
                                            , text detail.version
                                            ]
                                        , p []
                                            [ strong [] [ text "Software: " ]
                                            , text detail.softwareName
                                            ]
                                        , p []
                                            [ strong [] [ text "Customer: " ]
                                            , text (selectedCustomerName detail customerId)
                                            ]
                                        , p []
                                            [ strong [] [ text "Release date: " ]
                                            , text (formatDate detail.releaseDate)
                                            ]
                                        , p []
                                            [ strong [] [ text "Status: " ]
                                            , text statusLabel
                                            ]
                                        ]
                                    , p [] [ text ("Released by " ++ detail.releasedByName) ]
                                    , viewCustomerNotes detail customerId
                                    , viewInstallerActions model detail customerId isProductionReady
                                    ]

                            Nothing ->
                                case model.latestError of
                                    Just err ->
                                        div [ class "error" ] [ text err ]

                                    Nothing ->
                                        p [] [ text "No release data available for this combination." ]


viewCustomerNotes : VersionDetail -> Int -> Html Msg
viewCustomerNotes detail customerId =
    let
        customerSpecificNotes =
            detail.notes
                |> List.filter
                    (\note ->
                        List.any (\cust -> cust.id == customerId) note.customers
                    )
    in
    div [ class "notes-section" ]
        ([ h3 []
            [ text
                ("Release notes for "
                    ++ selectedCustomerName detail customerId
                    ++ " (version "
                    ++ detail.version
                    ++ ")"
                )
            ]
         ]
            ++ (if List.isEmpty customerSpecificNotes then
                    [ p [] [ text "No customer-specific notes were recorded for this release." ] ]

                else
                    [ div [ class "note-list" ]
                        (List.map viewNoteItem customerSpecificNotes)
                    ]
               )
        )


viewNoteItem : NoteDetail -> Html Msg
viewNoteItem note =
    div [ class "note-item" ]
        [ div [ class "note-text" ] [ Utils.NoteFormatter.formatNote note.note ]
        ]


viewInstallerActions : Model -> VersionDetail -> Int -> Bool -> Html Msg
viewInstallerActions model detail customerId isProductionReady =
    let
        buttonDisabled =
            case model.installerState of
                InstallerLaunching ->
                    True

                _ ->
                    False
    in
    div [ class "installer-actions" ]
        (if isProductionReady then
            [ button
                [ class "btn-primary"
                , onClick OpenInstallerClicked
                , disabled buttonDisabled
                ]
                [ text "Open Installer Creator" ]
            , viewInstallerStatus model.installerState detail customerId
            ]

         else
            [ div [ class "error" ]
                [ p []
                    [ text "No production-ready release is available. Contact the software department to request a production build." ]
                ]
            ]
        )


viewInstallerStatus : InstallerState -> VersionDetail -> Int -> Html msg
viewInstallerStatus state detail customerId =
    case state of
        InstallerIdle ->
            p [ class "help-text" ]
                [ text
                    ("The installer tool will launch locally and receive these parameters: "
                        ++ detail.softwareName
                        ++ ", "
                        ++ detail.version
                        ++ ", customer #"
                        ++ String.fromInt customerId
                    )
                ]

        InstallerLaunching ->
            p [ class "info" ] [ text "Opening installer application..." ]

        InstallerSuccess ->
            p [ class "success" ] [ text "Installer application launched. Complete the build steps in the Windows app." ]

        InstallerError err ->
            div [ class "error" ]
                [ p [] [ text "Failed to open installer application." ]
                , small [] [ text err ]
                ]


selectedCustomerName : VersionDetail -> Int -> String
selectedCustomerName detail customerId =
    detail.customers
        |> List.filter (\customer -> customer.id == customerId)
        |> List.head
        |> Maybe.map .name
        |> Maybe.withDefault "selected customer"


formatDate : String -> String
formatDate dateString =
    let
        datePart =
            dateString
                |> String.split "T"
                |> List.head
                |> Maybe.withDefault dateString
    in
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


releaseStageForCustomer : VersionDetail -> Int -> CustomerReleaseStage
releaseStageForCustomer detail customerId =
    detail.customers
        |> List.filter (\customer -> customer.id == customerId)
        |> List.head
        |> Maybe.map .releaseStage
        |> Maybe.withDefault CustomerPreRelease


releaseStatusFromStage : CustomerReleaseStage -> ReleaseStatus
releaseStatusFromStage stage =
    case stage of
        CustomerPreRelease ->
            PreRelease

        CustomerReleased ->
            Released

        CustomerProductionReady ->
            ProductionReady

        CustomerCanceled ->
            Canceled


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl badUrl ->
            "Bad URL: " ++ badUrl

        Http.Timeout ->
            "The request timed out."

        Http.NetworkError ->
            "Network error."

        Http.BadStatus statusCode ->
            "Server returned status " ++ String.fromInt statusCode ++ "."

        Http.BadBody details ->
            "Unable to parse server response: " ++ details
