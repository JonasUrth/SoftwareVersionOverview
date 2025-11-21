module Pages.Login exposing (Model, Msg, page)

import Api.Auth
import Dict
import Effect exposing (Effect)
import Gen.Params.Login exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onInput, onSubmit)
import Http
import Page
import Request exposing (Request)
import Shared
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init
        , update = update req
        , view = view
        , subscriptions = subscriptions
        }


-- INIT


type alias Model =
    { username : String
    , password : String
    , error : Maybe String
    , loading : Bool
    }


init : ( Model, Effect Msg )
init =
    ( { username = ""
      , password = ""
      , error = Nothing
      , loading = False
      }
    , Effect.none
    )


-- UPDATE


type Msg
    = UsernameChanged String
    | PasswordChanged String
    | FormSubmitted
    | LoginResponse (Result Http.Error Api.Auth.LoginResponse)


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        UsernameChanged username ->
            ( { model | username = username }, Effect.none )

        PasswordChanged password ->
            ( { model | password = password }, Effect.none )

        FormSubmitted ->
            ( { model | loading = True, error = Nothing }
            , Effect.fromCmd <|
                Api.Auth.login
                    { username = model.username
                    , password = model.password
                    }
                    LoginResponse
            )

        LoginResponse (Ok response) ->
            if response.success then
                case ( response.user, response.token ) of
                    ( Just user, Just token ) ->
                        -- Login successful - send user and token to Shared and navigate!
                        ( model
                        , Effect.batch
                            [ Effect.fromShared (Shared.UserLoggedIn user token)
                            , Effect.fromCmd (Request.pushRoute Route.Home_ req)
                            ]
                        )

                    ( Just _, Nothing ) ->
                        ( { model | error = Just "Login failed - no token received", loading = False }
                        , Effect.none
                        )

                    ( Nothing, _ ) ->
                        ( { model | error = Just "Login failed - no user data", loading = False }
                        , Effect.none
                        )

            else
                ( { model | error = Just response.message, loading = False }
                , Effect.none
                )

        LoginResponse (Err _) ->
            ( { model | error = Just "Network error. Is the backend running?", loading = False }
            , Effect.none
            )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


-- VIEW


view : Model -> View Msg
view model =
    { title = "Login - BM Release Manager"
    , body =
        [ div [ class "container" ]
            [ div [ class "login-box" ]
                [ h1 [] [ text "BM Release Manager" ]
                , h2 [] [ text "Login" ]
                , viewError model.error
                , Html.form [ onSubmit FormSubmitted ]
                    [ div [ class "form-group" ]
                        [ label [] [ text "Username" ]
                        , input
                            [ type_ "text"
                            , value model.username
                            , onInput UsernameChanged
                            , disabled model.loading
                            , placeholder "admin"
                            ]
                            []
                        ]
                    , div [ class "form-group" ]
                        [ label [] [ text "Password" ]
                        , input
                            [ type_ "password"
                            , value model.password
                            , onInput PasswordChanged
                            , disabled model.loading
                            , placeholder "Password"
                            ]
                            []
                        ]
                    , button
                        [ type_ "submit"
                        , class "btn-primary"
                        , disabled model.loading
                        ]
                        [ text
                            (if model.loading then
                                "Logging in..."

                             else
                                "Login"
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
