module Pages.Customers exposing (Model, Msg, page)

import Api.Auth
import Api.Data exposing (Customer, customerDecoder, customerEncoder)
import Api.Endpoint as Endpoint
import Effect exposing (Effect)
import Gen.Params.Customers exposing (Params)
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
    , formCountryId : Int
    , formIsActive : Bool
    , formRequiresValidation : Bool
    , editingId : Maybe Int
    , error : Maybe String
    , showInactive : Bool
    }


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ( { showForm = False
      , formName = ""
      , formCountryId = 0
      , formIsActive = True
      , formRequiresValidation = False
      , editingId = Nothing
      , error = Nothing
      , showInactive = False
      }
    , case shared.user of
        Just _ ->
            if List.isEmpty shared.customers then
                Effect.fromShared (Shared.RefreshCustomersWithInactive False)

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
    | CountryChanged String
    | IsActiveChanged Bool
    | RequiresValidationChanged Bool
    | FormSubmitted
    | CustomerCreated (Result Http.Error Customer)
    | CustomerUpdated (Result Http.Error ())
    | EditCustomer Customer
    | DeleteCustomer Int
    | CustomerDeleted Int (Result Http.Error ())
    | ToggleShowInactive
    | NavigateToRoute Route.Route
    | LogoutRequested
    | LogoutResponse (Result Http.Error ())
    | NoOp


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        ShowAddForm ->
            ( { model | showForm = True, formName = "", formCountryId = 0, formIsActive = True, formRequiresValidation = False, editingId = Nothing }, Effect.none )

        CancelForm ->
            ( { model | showForm = False, formName = "", formCountryId = 0, formIsActive = True, formRequiresValidation = False, editingId = Nothing }, Effect.none )

        NameChanged name ->
            ( { model | formName = name }, Effect.none )

        CountryChanged countryIdStr ->
            ( { model | formCountryId = String.toInt countryIdStr |> Maybe.withDefault 0 }, Effect.none )

        IsActiveChanged isActive ->
            ( { model | formIsActive = isActive }, Effect.none )

        RequiresValidationChanged val ->
            ( { model | formRequiresValidation = val }, Effect.none )

        FormSubmitted ->
            case model.editingId of
                Just id ->
                    ( model
                    , Effect.fromCmd <|
                        Http.request
                            { method = "PUT"
                            , headers = []
                            , url = Endpoint.customers [ String.fromInt id ]
                            , body =
                                Http.jsonBody <|
                                    customerEncoder
                                        { name = model.formName
                                        , countryId = model.formCountryId
                                        , isActive = model.formIsActive
                                        , requiresCustomerValidation = model.formRequiresValidation
                                        }
                            , expect = Http.expectWhatever CustomerUpdated
                            , timeout = Nothing
                            , tracker = Nothing
                            }
                    )

                Nothing ->
                    ( model
                    , Effect.fromCmd <|
                        Http.post
                            { url = Endpoint.customers []
                            , body =
                                Http.jsonBody <|
                                    customerEncoder
                                        { name = model.formName
                                        , countryId = model.formCountryId
                                        , isActive = model.formIsActive
                                        , requiresCustomerValidation = model.formRequiresValidation
                                        }
                            , expect = Http.expectJson CustomerCreated customerDecoder
                            }
                    )

        CustomerCreated (Ok customer) ->
            ( { model
                | showForm = False
                , formName = ""
                , formCountryId = 0
                , formIsActive = True
                , formRequiresValidation = False
                , error = Nothing
              }
            , Effect.fromShared Shared.RefreshCustomers
            )

        CustomerCreated (Err _) ->
            ( { model | error = Just "Failed to create customer" }, Effect.none )

        CustomerUpdated (Ok ()) ->
            ( { model
                | showForm = False
                , formName = ""
                , formCountryId = 0
                , formIsActive = True
                , formRequiresValidation = False
                , editingId = Nothing
                , error = Nothing
              }
            , Effect.fromShared Shared.RefreshCustomers
            )

        CustomerUpdated (Err _) ->
            ( { model | error = Just "Failed to update customer" }, Effect.none )

        EditCustomer customer ->
            ( { model
                | showForm = True
                , formName = customer.name
                , formCountryId = customer.countryId
                , formIsActive = customer.isActive
                , formRequiresValidation = customer.requiresCustomerValidation
                , editingId = Just customer.id
              }
            , Effect.none
            )

        DeleteCustomer id ->
            ( model
            , Effect.fromCmd <|
                Http.request
                    { method = "DELETE"
                    , headers = []
                    , url = Endpoint.customers [ String.fromInt id ]
                    , body = Http.emptyBody
                    , expect = Http.expectWhatever (CustomerDeleted id)
                    , timeout = Nothing
                    , tracker = Nothing
                    }
            )

        CustomerDeleted id (Ok ()) ->
            ( model, Effect.fromShared (Shared.RefreshCustomersWithInactive model.showInactive) )

        CustomerDeleted id (Err _) ->
            ( { model | error = Just "Failed to update customer" }, Effect.none )

        ToggleShowInactive ->
            ( { model | showInactive = not model.showInactive }
            , Effect.fromShared (Shared.RefreshCustomersWithInactive (not model.showInactive))
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
        , pageTitle = "Customers - BM Release Manager"
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
                        [ h1 [] [ text "Customers" ]
                        , button [ class "btn-primary", onClick ShowAddForm ] [ text "+ Add Customer" ]
                        ]
                    , viewError model.error
                    , viewFilterBar model
                    , viewCustomers shared.customers
                    , if model.showForm then
                        viewFormModal shared model

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


viewFilterBar : Model -> Html Msg
viewFilterBar model =
    div [ class "filter-bar", style "padding" "1rem", style "background" "#f8f9fa", style "margin-bottom" "1rem", style "border-radius" "4px" ]
        [ label [ style "display" "flex", style "align-items" "center", style "gap" "0.5rem", style "cursor" "pointer" ]
            [ input
                [ type_ "checkbox"
                , checked model.showInactive
                , onClick ToggleShowInactive
                ]
                []
            , text "Show Inactive Customers"
            ]
        ]


viewFormModal : Shared.Model -> Model -> Html Msg
viewFormModal shared model =
    div [ class "modal-overlay", onClick CancelForm ]
        [ div
            [ class "modal-content form-card"
            , Html.Events.stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
            ]
            [ h3 []
                [ text
                    (if model.editingId == Nothing then
                        "Add New Customer"

                     else
                        "Edit Customer"
                    )
                ]
            , Html.form [ onSubmit FormSubmitted ]
                [ div [ class "form-group" ]
                    [ label [] [ text "Customer Name" ]
                    , input
                        [ type_ "text"
                        , value model.formName
                        , onInput NameChanged
                        , placeholder "e.g., ACME Corp"
                        , required True
                        ]
                        []
                    ]
                , div [ class "form-group" ]
                    [ label [] [ text "Country" ]
                    , select
                        [ onInput CountryChanged
                        , required True
                        ]
                        (option [ value "0" ] [ text "-- Select Country --" ]
                            :: List.map
                                (\country ->
                                    option
                                        [ value (String.fromInt country.id)
                                        , selected (country.id == model.formCountryId)
                                        ]
                                        [ text country.name ]
                                )
                                shared.countries
                        )
                    ]
                , div [ class "form-group" ]
                    [ label []
                        [ input
                            [ type_ "checkbox"
                            , checked model.formIsActive
                            , onClick (IsActiveChanged (not model.formIsActive))
                            ]
                            []
                        , text " Active"
                        ]
                    ]
                , div [ class "form-group" ]
                    [ label []
                        [ input
                            [ type_ "checkbox"
                            , checked model.formRequiresValidation
                            , onClick (RequiresValidationChanged (not model.formRequiresValidation))
                            ]
                            []
                        , text " Requires Customer Validation"
                        ]
                    ]
                , div [ class "form-actions" ]
                    [ button [ type_ "button", class "btn-secondary", onClick CancelForm ] [ text "Cancel" ]
                    , button [ type_ "submit", class "btn-primary" ] [ text "Save" ]
                    ]
                ]
            ]
        ]


viewCustomers : List Customer -> Html Msg
viewCustomers customers =
    if List.isEmpty customers then
        p [ class "empty" ] [ text "No customers yet. Add one to get started!" ]

    else
        div [ class "table-container" ]
            [ table []
                [ thead []
                    [ tr []
                        [ th [] [ text "Name" ]
                        , th [] [ text "Country" ]
                        , th [] [ text "Status" ]
                        , th [] [ text "Requires Validation" ]
                        , th [] [ text "Actions" ]
                        ]
                    ]
                , tbody [] (List.map viewCustomerRow customers)
                ]
            ]


viewCustomerRow : Customer -> Html Msg
viewCustomerRow customer =
    tr
        [ classList
            [ ( "inactive", not customer.isActive )
            ]
        ]
        [ td [] [ text customer.name ]
        , td [] [ text customer.country.name ]
        , td []
            [ span
                [ class
                    (if customer.isActive then
                        "badge status-released"

                     else
                        "badge status-prerelease"
                    )
                ]
                [ text
                    (if customer.isActive then
                        "Active"

                     else
                        "Inactive"
                    )
                ]
            ]
        , td [] [ text (if customer.requiresCustomerValidation then "Yes" else "No") ]
        , td [ class "actions" ]
            [ button [ class "btn-small", onClick (EditCustomer customer) ] [ text "Edit" ]
            ]
        ]
