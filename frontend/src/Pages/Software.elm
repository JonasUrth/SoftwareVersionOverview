module Pages.Software exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (ReleaseMethod(..), Software, SoftwareType(..), releaseMethodFromString, releaseMethodToString, softwareDecoder, softwareEncoder, softwareTypeFromString, softwareTypeToString)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Software exposing (Params)
import Gen.Route as Route
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, preventDefaultOn)
import Http
import Json.Decode as Decode
import Layouts.Default
import Maybe
import Page
import Request
import Shared
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    let
        _ =
            req
    in
    Page.advanced
        { init = init shared req
        , update = update req
        , view = view shared req
        , subscriptions = subscriptions
        }


type alias Model =
    { showForm : Bool
    , formName : String
    , formType : String
    , formFileLocation : String
    , formReleaseMethod : Maybe ReleaseMethod
    , editingId : Maybe Int
    , error : Maybe String
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared _ =
    ( { showForm = False
      , formName = ""
      , formType = ""
      , formFileLocation = ""
      , formReleaseMethod = Nothing
      , editingId = Nothing
      , error = Nothing
      }
    , case shared.user of
        Just _ ->
            if List.isEmpty shared.software then
                Effect.fromShared Shared.RefreshSoftware

            else
                Effect.none

        Nothing ->
            Effect.none
    )


type Msg
    = ShowAddForm
    | CancelForm
    | NameChanged String
    | TypeChanged String
    | FileLocationChanged String
    | ReleaseMethodChanged String
    | FormSubmitted
    | SoftwareCreated (Result Http.Error Software)
    | EditSoftware Software
    | SoftwareUpdated Int (Result Http.Error ())
    | DeleteSoftware Int
    | SoftwareDeleted Int (Result Http.Error ())
    | NavigateToRoute Route.Route
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        ShowAddForm ->
            ( { model
                | showForm = True
                , formName = ""
                , formType = ""
                , formFileLocation = ""
                , formReleaseMethod = Nothing
                , editingId = Nothing
              }
            , Effect.none
            )

        CancelForm ->
            ( { model
                | showForm = False
                , formName = ""
                , formType = ""
                , formFileLocation = ""
                , formReleaseMethod = Nothing
                , editingId = Nothing
              }
            , Effect.none
            )

        NameChanged name ->
            ( { model | formName = name }, Effect.none )

        TypeChanged type_ ->
            ( { model | formType = type_ }, Effect.none )

        FileLocationChanged loc ->
            ( { model | formFileLocation = loc }, Effect.none )

        ReleaseMethodChanged method ->
            let
                parsedMethod =
                    if String.isEmpty method then
                        Nothing

                    else
                        releaseMethodFromString method
            in
            ( { model | formReleaseMethod = parsedMethod }, Effect.none )

        FormSubmitted ->
            let
                requestBody =
                    Http.jsonBody <|
                        softwareEncoder
                            { name = model.formName
                            , type_ = softwareTypeFromString model.formType
                            , fileLocation =
                                if String.isEmpty model.formFileLocation then
                                    Nothing

                                else
                                    Just model.formFileLocation
                            , releaseMethod =
                                model.formReleaseMethod
                            }
            in
            case model.editingId of
                Nothing ->
                    ( model
                    , Effect.fromCmd <|
                        Http.request
                            { method = "POST"
                            , headers = []
                            , url = Endpoint.software []
                            , body = requestBody
                            , expect = Http.expectStringResponse SoftwareCreated decodeSoftwareResponse
                            , timeout = Nothing
                            , tracker = Nothing
                            }
                    )

                Just id ->
                    ( model
                    , Effect.fromCmd <|
                        Http.request
                            { method = "PUT"
                            , headers = []
                            , url = Endpoint.software [ String.fromInt id ]
                            , body = requestBody
                            , expect = Http.expectWhatever (SoftwareUpdated id)
                            , timeout = Nothing
                            , tracker = Nothing
                            }
                    )

        SoftwareCreated (Ok _) ->
            ( { model
                | showForm = False
                , formName = ""
                , formType = ""
                , formFileLocation = ""
                , formReleaseMethod = Nothing
                , editingId = Nothing
                , error = Nothing
              }
            , Effect.fromShared Shared.RefreshSoftware
            )

        SoftwareCreated (Err err) ->
            ( { model | error = Just ("Failed to create software: " ++ httpErrorToString err) }, Effect.none )

        EditSoftware sw ->
            ( { model
                | showForm = True
                , formName = sw.name
                , formType = softwareTypeToString sw.type_
                , formFileLocation = Maybe.withDefault "" sw.fileLocation
                , formReleaseMethod = sw.releaseMethod
                , editingId = Just sw.id
              }
            , Effect.none
            )

        SoftwareUpdated _ (Ok ()) ->
            ( { model
                | showForm = False
                , formName = ""
                , formType = ""
                , formFileLocation = ""
                , formReleaseMethod = Nothing
                , editingId = Nothing
                , error = Nothing
              }
            , Effect.fromShared Shared.RefreshSoftware
            )

        SoftwareUpdated _ (Err err) ->
            ( { model | error = Just ("Failed to update software: " ++ httpErrorToString err) }, Effect.none )

        DeleteSoftware id ->
            ( model
            , Effect.fromCmd <|
                Http.request
                    { method = "DELETE"
                    , headers = []
                    , url = Endpoint.software [ String.fromInt id ]
                    , body = Http.emptyBody
                    , expect = Http.expectWhatever (SoftwareDeleted id)
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        SoftwareDeleted _ (Ok ()) ->
            ( model, Effect.fromShared Shared.RefreshSoftware )

        SoftwareDeleted _ (Err _) ->
            ( { model | error = Just "Failed to delete" }, Effect.none )

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


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    Layouts.Default.view
        { shared = shared
        , req = req
        , pageTitle = "Software - BM Release Manager"
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
                        [ h1 [] [ text "Software" ]
                        , button [ class "btn-primary", onClick ShowAddForm ] [ text "+ Add Software" ]
                        ]
                    , viewError model.error
                    , if model.showForm then
                        viewForm model

                      else
                        text ""
                    , viewSoftwareList shared.software
                    ]
        , onNavigate = NavigateToRoute
        , onLogout = LogoutRequested
        }


viewError : Maybe String -> Html Msg
viewError maybeError =
    case maybeError of
        Just errMsg ->
            div [ class "alert alert-error" ]
                [ text errMsg ]

        Nothing ->
            text ""


viewForm : Model -> Html Msg
viewForm model =
    div [ class "form-card" ]
        [ h3 []
            [ text
                (if model.editingId == Nothing then
                    "Add New Software"

                 else
                    "Edit Software"
                )
            ]
        , Html.form [ onSubmit FormSubmitted ]
            [ div [ class "form-group" ]
                [ label [] [ text "Name" ]
                , input [ type_ "text", value model.formName, onInput NameChanged, required True ] []
                ]
            , div [ class "form-group" ]
                [ label [] [ text "Type" ]
                , select [ onInput TypeChanged, required True ]
                    [ option [ value "" ] [ text "-- Select Type --" ]
                    , option [ value "Firmware", selected (model.formType == "Firmware") ] [ text "Firmware" ]
                    , option [ value "Windows", selected (model.formType == "Windows") ] [ text "Windows" ]
                    ]
                ]
            , div [ class "form-group" ]
                [ label [] [ text "File Location" ]
                , input [ type_ "text", value model.formFileLocation, onInput FileLocationChanged, placeholder "L:\\_Software\\Releases\\Firmware - Eprom\\x200F\\{{VERSION}}" ] []
                , small [ style "color" "#666", style "font-size" "0.9em" ]
                    [ text "Example: L:\\_Software\\Releases\\Firmware - Eprom\\x200F\\{{VERSION}}.bin" ]
                ]
            , div [ class "form-group" ]
                [ label [] [ text "Release Method" ]
                , select [ onInput ReleaseMethodChanged ]
                    [ option [ value "", selected (model.formReleaseMethod == Nothing) ] [ text "-- Select Release Method --" ]
                    , option
                        [ value (releaseMethodToString FindFile)
                        , selected (model.formReleaseMethod == Just FindFile)
                        ]
                        [ text "Find file" ]
                    , option
                        [ value (releaseMethodToString CreateCD)
                        , selected (model.formReleaseMethod == Just CreateCD)
                        ]
                        [ text "Create CD" ]
                    , option
                        [ value (releaseMethodToString FindFolder)
                        , selected (model.formReleaseMethod == Just FindFolder)
                        ]
                        [ text "Find folder" ]
                    ]
                ]
            , div [ class "form-actions" ]
                [ button [ type_ "button", class "btn-secondary", onClick CancelForm ] [ text "Cancel" ]
                , button [ type_ "submit", class "btn-primary" ]
                    [ text
                        (if model.editingId == Nothing then
                            "Save"

                         else
                            "Update"
                        )
                    ]
                ]
            ]
        ]


viewSoftwareList : List Software -> Html Msg
viewSoftwareList software =
    if List.isEmpty software then
        p [ class "empty" ] [ text "No software yet" ]

    else
        div [ class "table-container" ]
            [ table []
                [ thead []
                    [ tr []
                        [ th [] [ text "Name" ]
                        , th [] [ text "Type" ]
                        , th [] [ text "Actions" ]
                        ]
                    ]
                , tbody [] (List.map viewSoftwareRow software)
                ]
            ]


viewSoftwareRow : Software -> Html Msg
viewSoftwareRow sw =
    tr []
        [ td [] [ text sw.name ]
        , td [] [ text (formatSoftwareType sw.type_) ]
        , td [ class "actions" ]
            [ button [ class "btn-small", onClick (EditSoftware sw) ] [ text "Edit" ]
            , button [ class "btn-small btn-danger", onClick (DeleteSoftware sw.id) ] [ text "Delete" ]
            ]
        ]


formatSoftwareType : SoftwareType -> String
formatSoftwareType type_ =
    softwareTypeToString type_


decodeSoftwareResponse : Http.Response String -> Result Http.Error Software
decodeSoftwareResponse response =
    case response of
        Http.BadUrl_ badUrl ->
            Err (Http.BadUrl badUrl)

        Http.Timeout_ ->
            Err Http.Timeout

        Http.NetworkError_ ->
            Err Http.NetworkError

        Http.BadStatus_ _ body ->
            Err (Http.BadBody body)

        Http.GoodStatus_ _ body ->
            case Decode.decodeString softwareDecoder body of
                Ok value ->
                    Ok value

                Err err ->
                    Err (Http.BadBody (Decode.errorToString err))


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl badUrl ->
            "Bad URL: " ++ badUrl

        Http.Timeout ->
            "Request timed out."

        Http.NetworkError ->
            "Network error."

        Http.BadStatus statusCode ->
            "Server returned status " ++ String.fromInt statusCode ++ "."

        Http.BadBody details ->
            details
