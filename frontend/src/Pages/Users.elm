module Pages.Users exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (User, userDecoder, userEncoder, userUpdateEncoder)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Users exposing (Params)
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
        , update = update shared req
        , view = view shared req
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { showForm : Bool
    , formName : String
    , formPassword : String
    , editingId : Maybe Int
    , error : Maybe String
    , users : List User
    , loading : Bool
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { showForm = False
      , formName = ""
      , formPassword = ""
      , editingId = Nothing
      , error = Nothing
      , users = []
      , loading = True
      }
    , case shared.user of
        Just _ ->
            Effect.fromCmd (fetchUsers shared.token)

        Nothing ->
            Effect.none
    )


authHeaders : Maybe String -> List Http.Header
authHeaders token =
    case token of
        Just t ->
            [ Http.header "Authorization" ("Basic " ++ t) ]

        Nothing ->
            []


fetchUsers : Maybe String -> Cmd Msg
fetchUsers token =
    Http.request
        { method = "GET"
        , headers = authHeaders token
        , url = Endpoint.users []
        , body = Http.emptyBody
        , expect = Http.expectJson GotUsers (Decode.list userDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


-- UPDATE


type Msg
    = ShowAddForm
    | CancelForm
    | NameChanged String
    | PasswordChanged String
    | FormSubmitted
    | UserCreated (Result Http.Error User)
    | EditUser User
    | DeleteUser Int
    | UserDeleted Int (Result Http.Error ())
    | UserUpdated (Result Http.Error ())
    | GotUsers (Result Http.Error (List User))
    | NavigateToRoute Route.Route
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        ShowAddForm ->
            ( { model | showForm = True, formName = "", formPassword = "", editingId = Nothing }, Effect.none )

        CancelForm ->
            ( { model | showForm = False, formName = "", formPassword = "", editingId = Nothing }, Effect.none )

        NameChanged name ->
            ( { model | formName = name }, Effect.none )

        PasswordChanged password ->
            ( { model | formPassword = password }, Effect.none )

        FormSubmitted ->
            case model.editingId of
                Just id ->
                    ( model
                    , Effect.fromCmd <|
                        Http.request
                            { method = "PUT"
                            , headers = authHeaders shared.token
                            , url = Endpoint.users [ String.fromInt id ]
                            , body = Http.jsonBody (userUpdateEncoder { id = id, name = model.formName, password = model.formPassword })
                            , expect = Http.expectWhatever UserUpdated
                            , timeout = Nothing
                            , tracker = Nothing
                            }
                    )

                Nothing ->
                    ( model
                    , Effect.fromCmd <|
                        Http.request
                            { method = "POST"
                            , headers = authHeaders shared.token
                            , url = Endpoint.users []
                            , body = Http.jsonBody (userEncoder { name = model.formName, password = model.formPassword })
                            , expect = Http.expectJson UserCreated userDecoder
                            , timeout = Nothing
                            , tracker = Nothing
                            }
                    )

        UserCreated (Ok user) ->
            ( { model
                | showForm = False
                , formName = ""
                , formPassword = ""
                , error = Nothing
              }
            , Effect.fromCmd (fetchUsers shared.token)
            )

        UserCreated (Err _) ->
            ( { model | error = Just "Failed to create user" }, Effect.none )

        UserUpdated (Ok ()) ->
            ( { model
                | showForm = False
                , formName = ""
                , formPassword = ""
                , editingId = Nothing
                , error = Nothing
              }
            , Effect.fromCmd (fetchUsers shared.token)
            )

        UserUpdated (Err _) ->
            ( { model | error = Just "Failed to update user" }, Effect.none )

        EditUser user ->
            ( { model
                | showForm = True
                , formName = user.name
                , formPassword = ""
                , editingId = Just user.id
              }
            , Effect.none
            )

        DeleteUser id ->
            ( model
            , Effect.fromCmd <|
                Http.request
                    { method = "DELETE"
                    , headers = authHeaders shared.token
                    , url = Endpoint.users [ String.fromInt id ]
                    , body = Http.emptyBody
                    , expect = Http.expectWhatever (UserDeleted id)
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        UserDeleted id (Ok ()) ->
            ( model, Effect.fromCmd (fetchUsers shared.token) )

        UserDeleted id (Err _) ->
            ( { model | error = Just "Failed to delete user" }, Effect.none )

        GotUsers (Ok users) ->
            ( { model | users = users, loading = False, error = Nothing }, Effect.none )

        GotUsers (Err _) ->
            ( { model | loading = False, error = Just "Failed to load users" }, Effect.none )

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
        , pageTitle = "Users - BM Release Manager"
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
                        [ h1 [] [ text "Users" ]
                        , button [ class "btn-primary", onClick ShowAddForm ] [ text "+ Add User" ]
                        ]
                    , viewError model.error
                    , if model.loading then
                        p [] [ text "Loading users..." ]

                      else if model.showForm then
                        viewForm model

                      else
                        text ""
                    , viewUsers model.users
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


viewForm : Model -> Html Msg
viewForm model =
    div [ class "form-card" ]
        [ h3 []
            [ text
                (if model.editingId == Nothing then
                    "Add New User"

                 else
                    "Edit User"
                )
            ]
        , Html.form [ onSubmit FormSubmitted ]
            [ div [ class "form-group" ]
                [ label [] [ text "Username" ]
                , input
                    [ type_ "text"
                    , value model.formName
                    , onInput NameChanged
                    , placeholder "e.g., admin"
                    , required True
                    ]
                    []
                ]
            , div [ class "form-group" ]
                [ label [] [ text "Password" ]
                , input
                    [ type_ "password"
                    , value model.formPassword
                    , onInput PasswordChanged
                    , placeholder
                        (if model.editingId == Nothing then
                            "Enter password"

                         else
                            "Enter new password (leave blank to keep current)"
                        )
                    , required (model.editingId == Nothing)
                    ]
                    []
                ]
            , div [ class "form-actions" ]
                [ button [ type_ "button", class "btn-secondary", onClick CancelForm ] [ text "Cancel" ]
                , button [ type_ "submit", class "btn-primary" ] [ text "Save" ]
                ]
            ]
        ]


viewUsers : List User -> Html Msg
viewUsers users =
    if List.isEmpty users then
        p [ class "empty" ] [ text "No users yet. Add one to get started!" ]

    else
        div [ class "table-container" ]
            [ table []
                [ thead []
                    [ tr []
                        [ th [] [ text "ID" ]
                        , th [] [ text "Username" ]
                        , th [] [ text "Actions" ]
                        ]
                    ]
                , tbody [] (List.map viewUserRow users)
                ]
            ]


viewUserRow : User -> Html Msg
viewUserRow user =
    tr []
        [ td [] [ text (String.fromInt user.id) ]
        , td [] [ text user.name ]
        , td [ class "actions" ]
            [ button [ class "btn-small", onClick (EditUser user) ] [ text "Edit" ]
            , button [ class "btn-small btn-danger", onClick (DeleteUser user.id) ] [ text "Delete" ]
            ]
        ]
