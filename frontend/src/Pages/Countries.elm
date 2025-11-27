module Pages.Countries exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (Country, countryDecoder, countryEncoder)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Countries exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, preventDefaultOn)
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
        , update = update req
        , view = view shared req
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { showForm : Bool
    , formName : String
    , formNote : String
    , editingId : Maybe Int
    , error : Maybe String
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { showForm = False
      , formName = ""
      , formNote = ""
      , editingId = Nothing
      , error = Nothing
      }
    , case shared.user of
        Just _ ->
            if List.isEmpty shared.countries then
                Effect.fromShared Shared.RefreshCountries

            else
                Effect.none

        Nothing ->
            Effect.none
    )


-- UPDATE


type Msg
    = ShowAddForm
    | CancelForm
    | NameChanged String
    | NoteChanged String
    | FormSubmitted
    | CountryCreated (Result Http.Error Country)
    | CountryUpdated (Result Http.Error ())
    | EditCountry Country
    | NavigateToRoute Route.Route
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())
    | NoOp


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        ShowAddForm ->
            ( { model | showForm = True, formName = "", formNote = "", editingId = Nothing }, Effect.none )

        CancelForm ->
            ( { model | showForm = False, formName = "", formNote = "", editingId = Nothing }, Effect.none )

        NameChanged name ->
            ( { model | formName = name }, Effect.none )

        NoteChanged note ->
            ( { model | formNote = note }, Effect.none )

        FormSubmitted ->
            let
                endpoint =
                    case model.editingId of
                        Just id ->
                            Endpoint.countries [ String.fromInt id ]

                        Nothing ->
                            Endpoint.countries []

                method =
                    case model.editingId of
                        Just _ ->
                            "PUT"

                        Nothing ->
                            "POST"

                expect =
                    case model.editingId of
                        Just _ ->
                            Http.expectWhatever CountryUpdated

                        Nothing ->
                            Http.expectJson CountryCreated countryDecoder
            in
            ( model
            , Effect.fromCmd <|
                Http.request
                    { method = method
                    , headers = []
                    , url = endpoint
                    , body =
                        Http.jsonBody <|
                            countryEncoder
                                { name = model.formName
                                , firmwareReleaseNote =
                                    if String.isEmpty model.formNote then
                                        Nothing

                                    else
                                        Just model.formNote
                                }
                    , expect = expect
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        CountryCreated (Ok country) ->
            ( { model
                | showForm = False
                , formName = ""
                , formNote = ""
                , error = Nothing
              }
            , Effect.fromShared Shared.RefreshCountries
            )

        CountryCreated (Err _) ->
            ( { model | error = Just "Failed to create country" }, Effect.none )

        CountryUpdated (Ok ()) ->
            ( { model
                | showForm = False
                , formName = ""
                , formNote = ""
                , editingId = Nothing
                , error = Nothing
              }
            , Effect.fromShared Shared.RefreshCountries
            )

        CountryUpdated (Err _) ->
            ( { model | error = Just "Failed to update country" }, Effect.none )

        EditCountry country ->
            ( { model
                | showForm = True
                , formName = country.name
                , formNote = Maybe.withDefault "" country.firmwareReleaseNote
                , editingId = Just country.id
              }
            , Effect.none
            )

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

        NoOp ->
            ( model, Effect.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


-- VIEW


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    Layouts.Default.view
        { shared = shared
        , req = req
        , pageTitle = "Countries - BM Release Manager"
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
                        [ h1 [] [ text "Countries" ]
                        , button [ class "btn-primary", onClick ShowAddForm ] [ text "+ Add Country" ]
                        ]
                    , viewError model.error
                    , viewCountries shared.countries
                    , if model.showForm then
                        viewFormModal model

                      else
                        text ""
                    ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewError : Maybe String -> Html Msg
viewError error =
    case error of
        Just err ->
            div [ class "error" ] [ text err ]

        Nothing ->
            text ""


viewFormModal : Model -> Html Msg
viewFormModal model =
    div [ class "modal-overlay", onClick CancelForm ]
        [ div
            [ class "modal-content form-card"
            , Html.Events.stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
            ]
            [ h3 []
                [ text
                    (if model.editingId == Nothing then
                        "Add New Country"

                     else
                        "Edit Country"
                    )
                ]
            , Html.form [ onSubmit FormSubmitted ]
                [ div [ class "form-group" ]
                    [ label [] [ text "Country Name" ]
                    , input
                        [ type_ "text"
                        , value model.formName
                        , onInput NameChanged
                        , placeholder "e.g., Denmark"
                        , required True
                        ]
                        []
                    ]
                , div [ class "form-group" ]
                    [ label [] [ text "Firmware Release Note" ]
                    , textarea
                        [ value model.formNote
                        , onInput NoteChanged
                        , placeholder "Configuration notes for production..."
                        , rows 3
                        ]
                        []
                    ]
                , div [ class "form-actions" ]
                    [ button [ type_ "button", class "btn-secondary", onClick CancelForm ] [ text "Cancel" ]
                    , button [ type_ "submit", class "btn-primary" ] [ text "Save" ]
                    ]
                ]
            ]
        ]


viewCountries : List Country -> Html Msg
viewCountries countries =
    if List.isEmpty countries then
        p [ class "empty" ] [ text "No countries yet. Add one to get started!" ]

    else
        div [ class "table-container" ]
            [ table []
                [ thead []
                    [ tr []
                        [ th [] [ text "Name" ]
                        , th [] [ text "Firmware Release Note" ]
                        , th [] [ text "Actions" ]
                        ]
                    ]
                , tbody [] (List.map viewCountryRow countries)
                ]
            ]


viewCountryRow : Country -> Html Msg
viewCountryRow country =
    tr
        [ classList
            [ ( "inactive", not country.isActive )
            ]
        ]
        [ td [] [ text country.name ]
        , td [] [ text (Maybe.withDefault "-" country.firmwareReleaseNote) ]
        , td [ class "actions" ]
            [ button [ class "btn-small", onClick (EditCountry country) ] [ text "Edit" ]
            ]
        ]
