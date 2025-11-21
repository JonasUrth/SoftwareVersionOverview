module Pages.Countries exposing (Model, Msg, page)

import Api.Data exposing (Country, countryDecoder, countryEncoder)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Countries exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Layouts.Default
import Page
import Request
import Shared
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared
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


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { showForm = False
      , formName = ""
      , formNote = ""
      , editingId = Nothing
      , error = Nothing
      }
    , if List.isEmpty shared.countries then
        Effect.fromShared Shared.RefreshCountries

      else
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
    | EditCountry Country
    | DeleteCountry Int
    | CountryDeleted Int (Result Http.Error ())
    | NavigateToRoute Route.Route


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
            ( model
            , Effect.fromCmd <|
                Http.post
                    { url = Endpoint.countries []
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
                    , expect = Http.expectJson CountryCreated countryDecoder
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

        EditCountry country ->
            ( { model
                | showForm = True
                , formName = country.name
                , formNote = Maybe.withDefault "" country.firmwareReleaseNote
                , editingId = Just country.id
              }
            , Effect.none
            )

        DeleteCountry id ->
            ( model
            , Effect.fromCmd <|
                Http.request
                    { method = "DELETE"
                    , headers = []
                    , url = Endpoint.countries [ String.fromInt id ]
                    , body = Http.emptyBody
                    , expect = Http.expectWhatever (CountryDeleted id)
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        CountryDeleted id (Ok ()) ->
            ( model, Effect.fromShared Shared.RefreshCountries )

        CountryDeleted id (Err _) ->
            ( { model | error = Just "Failed to delete country" }, Effect.none )

        NavigateToRoute route ->
            ( model, Effect.fromCmd (Request.pushRoute route req) )


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
            [ div [ class "header" ]
                [ h1 [] [ text "Countries" ]
                , button [ class "btn-primary", onClick ShowAddForm ] [ text "+ Add Country" ]
                ]
            , viewError model.error
            , if model.showForm then
                viewForm model

              else
                text ""
            , viewCountries shared.countries
            ]
        , onNavigate = NavigateToRoute
        }


viewError : Maybe String -> Html Msg
viewError error =
    case error of
        Just err ->
            div [ class "error" ] [ text err ]

        Nothing ->
            text ""


viewForm : Model -> Html Msg
viewForm model =
    div [ class "form-card" ]
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
    tr []
        [ td [] [ text country.name ]
        , td [] [ text (Maybe.withDefault "-" country.firmwareReleaseNote) ]
        , td [ class "actions" ]
            [ button [ class "btn-small", onClick (EditCountry country) ] [ text "Edit" ]
            , button [ class "btn-small btn-danger", onClick (DeleteCountry country.id) ] [ text "Delete" ]
            ]
        ]
