module Api.Data exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


-- USER


type alias User =
    { id : Int
    , name : String
    }


userDecoder : Decoder User
userDecoder =
    Decode.map2 User
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)


userEncoder : { name : String, password : String } -> Encode.Value
userEncoder data =
    Encode.object
        [ ( "name", Encode.string data.name )
        , ( "password", Encode.string data.password )
        ]


userUpdateEncoder : { id : Int, name : String, password : String } -> Encode.Value
userUpdateEncoder data =
    Encode.object
        [ ( "id", Encode.int data.id )
        , ( "name", Encode.string data.name )
        , ( "password", Encode.string data.password )
        ]


-- COUNTRY


type alias Country =
    { id : Int
    , name : String
    , firmwareReleaseNote : Maybe String
    }


countryDecoder : Decoder Country
countryDecoder =
    Decode.map3 Country
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "firmwareReleaseNote" Decode.string))


countryEncoder : { name : String, firmwareReleaseNote : Maybe String } -> Encode.Value
countryEncoder data =
    Encode.object
        [ ( "name", Encode.string data.name )
        , ( "firmwareReleaseNote"
          , case data.firmwareReleaseNote of
                Just note ->
                    Encode.string note

                Nothing ->
                    Encode.null
          )
        ]


-- CUSTOMER


type alias Customer =
    { id : Int
    , name : String
    , isActive : Bool
    , countryId : Int
    , country : Country
    , requiresCustomerValidation : Bool
    }


customerDecoder : Decoder Customer
customerDecoder =
    Decode.map6 Customer
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "isActive" Decode.bool)
        (Decode.field "countryId" Decode.int)
        (Decode.field "country" countryDecoder)
        (Decode.field "requiresCustomerValidation" Decode.bool)


customerEncoder : { name : String, countryId : Int, isActive : Bool, requiresCustomerValidation : Bool } -> Encode.Value
customerEncoder data =
    Encode.object
        [ ( "name", Encode.string data.name )
        , ( "countryId", Encode.int data.countryId )
        , ( "isActive", Encode.bool data.isActive )
        , ( "requiresCustomerValidation", Encode.bool data.requiresCustomerValidation )
        ]


-- SOFTWARE TYPE


type SoftwareType
    = Firmware
    | Windows


softwareTypeToString : SoftwareType -> String
softwareTypeToString softwareType =
    case softwareType of
        Firmware ->
            "Firmware"

        Windows ->
            "Windows"


softwareTypeFromString : String -> SoftwareType
softwareTypeFromString str =
    case str of
        "Firmware" ->
            Firmware

        "Windows" ->
            Windows

        _ ->
            Firmware


softwareTypeDecoder : Decoder SoftwareType
softwareTypeDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "Firmware" ->
                        Decode.succeed Firmware

                    "Windows" ->
                        Decode.succeed Windows

                    _ ->
                        Decode.fail ("Unknown software type: " ++ str)
            )


-- RELEASE METHOD


type ReleaseMethod
    = FindFile
    | CreateCD
    | FindFolder


releaseMethodToString : ReleaseMethod -> String
releaseMethodToString method =
    case method of
        FindFile ->
            "FindFile"

        CreateCD ->
            "CreateCD"

        FindFolder ->
            "FindFolder"


releaseMethodFromString : String -> Maybe ReleaseMethod
releaseMethodFromString str =
    case str of
        "FindFile" ->
            Just FindFile

        "CreateCD" ->
            Just CreateCD

        "FindFolder" ->
            Just FindFolder

        _ ->
            Nothing


releaseMethodDecoder : Decoder ReleaseMethod
releaseMethodDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case releaseMethodFromString str of
                    Just method ->
                        Decode.succeed method

                    Nothing ->
                        Decode.fail ("Unknown release method: " ++ str)
            )


-- RELEASE PATH CHECK


type alias ReleasePathCheckResponse =
    { isValid : Bool
    , errors : List String
    , warnings : List String
    }


releasePathCheckDecoder : Decoder ReleasePathCheckResponse
releasePathCheckDecoder =
    Decode.map3 ReleasePathCheckResponse
        (Decode.field "isValid" Decode.bool)
        (Decode.field "errors" (Decode.list Decode.string))
        (Decode.field "warnings" (Decode.list Decode.string))


-- SOFTWARE


type alias Software =
    { id : Int
    , name : String
    , type_ : SoftwareType
    , fileLocation : Maybe String
    , releaseMethod : Maybe ReleaseMethod
    }


softwareDecoder : Decoder Software
softwareDecoder =
    Decode.map5 Software
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "type" softwareTypeDecoder)
        (Decode.maybe (Decode.field "fileLocation" Decode.string))
        (Decode.maybe (Decode.field "releaseMethod" releaseMethodDecoder))


softwareEncoder : { name : String, type_ : SoftwareType, fileLocation : Maybe String, releaseMethod : Maybe ReleaseMethod } -> Encode.Value
softwareEncoder data =
    Encode.object
        [ ( "name", Encode.string data.name )
        , ( "type", Encode.string (softwareTypeToString data.type_) )
        , ( "fileLocation"
          , case data.fileLocation of
                Just loc ->
                    Encode.string loc

                Nothing ->
                    Encode.null
          )
        , ( "releaseMethod"
          , case data.releaseMethod of
                Just method ->
                    Encode.string (releaseMethodToString method)

                Nothing ->
                    Encode.null
          )
        ]


-- RELEASE STATUS


type ReleaseStatus
    = PreRelease
    | Released
    | ProductionReady
    | CustomPerCustomer


type CustomerReleaseStage
    = CustomerPreRelease
    | CustomerReleased
    | CustomerProductionReady


customerReleaseStageToString : CustomerReleaseStage -> String
customerReleaseStageToString stage =
    case stage of
        CustomerPreRelease ->
            "PreRelease"

        CustomerReleased ->
            "Released"

        CustomerProductionReady ->
            "ProductionReady"


customerReleaseStageFromString : String -> CustomerReleaseStage
customerReleaseStageFromString str =
    case str of
        "PreRelease" ->
            CustomerPreRelease

        "Released" ->
            CustomerReleased

        "ProductionReady" ->
            CustomerProductionReady

        _ ->
            CustomerReleased


customerReleaseStageDecoder : Decoder CustomerReleaseStage
customerReleaseStageDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "PreRelease" ->
                        Decode.succeed CustomerPreRelease

                    "Released" ->
                        Decode.succeed CustomerReleased

                    "ProductionReady" ->
                        Decode.succeed CustomerProductionReady

                    _ ->
                        Decode.fail ("Unknown customer release stage: " ++ str)
            )


releaseStatusToString : ReleaseStatus -> String
releaseStatusToString status =
    case status of
        PreRelease ->
            "PreRelease"

        Released ->
            "Released"

        ProductionReady ->
            "ProductionReady"

        CustomPerCustomer ->
            "CustomPerCustomer"


releaseStatusLabel : ReleaseStatus -> String
releaseStatusLabel status =
    case status of
        PreRelease ->
            "Pre-Release"

        Released ->
            "Released"

        ProductionReady ->
            "Production Ready"

        CustomPerCustomer ->
            "Individual Customer Releases"


releaseStatusFromString : String -> ReleaseStatus
releaseStatusFromString str =
    case str of
        "PreRelease" ->
            PreRelease

        "Released" ->
            Released

        "ProductionReady" ->
            ProductionReady

        "CustomPerCustomer" ->
            CustomPerCustomer

        _ ->
            Released


releaseStatusDecoder : Decoder ReleaseStatus
releaseStatusDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "PreRelease" ->
                        Decode.succeed PreRelease

                    "Released" ->
                        Decode.succeed Released

                    "ProductionReady" ->
                        Decode.succeed ProductionReady

                    "CustomPerCustomer" ->
                        Decode.succeed CustomPerCustomer

                    _ ->
                        Decode.fail ("Unknown release status: " ++ str)
            )


-- VERSION HISTORY


type alias Version =
    { id : Int
    , version : String
    , softwareId : Int
    , softwareName : String
    , releaseDate : String
    , releaseStatus : ReleaseStatus
    , releasedBy : String
    , customerCount : Int
    }


versionDecoder : Decoder Version
versionDecoder =
    Decode.map8 Version
        (Decode.field "id" Decode.int)
        (Decode.field "version" Decode.string)
        (Decode.field "softwareId" Decode.int)
        (Decode.field "softwareName" Decode.string)
        (Decode.field "releaseDate" Decode.string)
        (Decode.field "releaseStatus" releaseStatusDecoder)
        (Decode.field "releasedBy" Decode.string)
        (Decode.field "customerCount" Decode.int)


type alias CustomerDetail =
    { id : Int
    , name : String
    , isActive : Bool
    , countryName : String
    , releaseStage : CustomerReleaseStage
    }


customerDetailDecoder : Decoder CustomerDetail
customerDetailDecoder =
    Decode.map5 CustomerDetail
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "isActive" Decode.bool)
        (Decode.field "countryName" Decode.string)
        (Decode.field "releaseStage" customerReleaseStageDecoder)


type alias NoteDetail =
    { id : Int
    , note : String
    , customers : List CustomerDetail
    }


noteDetailDecoder : Decoder NoteDetail
noteDetailDecoder =
    Decode.map3 NoteDetail
        (Decode.field "id" Decode.int)
        (Decode.field "note" Decode.string)
        (Decode.field "customers" (Decode.list customerDetailDecoder))


type alias VersionDetail =
    { id : Int
    , version : String
    , softwareId : Int
    , softwareName : String
    , releaseDate : String
    , releaseStatus : ReleaseStatus
    , releasedByName : String
    , customers : List CustomerDetail
    , notes : List NoteDetail
    }


versionDetailDecoder : Decoder VersionDetail
versionDetailDecoder =
    Decode.map8
        (\id version softwareId softwareName releaseDate releaseStatus releasedByName customers ->
            \notes ->
                { id = id
                , version = version
                , softwareId = softwareId
                , softwareName = softwareName
                , releaseDate = releaseDate
                , releaseStatus = releaseStatus
                , releasedByName = releasedByName
                , customers = customers
                , notes = notes
                }
        )
        (Decode.field "id" Decode.int)
        (Decode.field "version" Decode.string)
        (Decode.field "softwareId" Decode.int)
        (Decode.field "softwareName" Decode.string)
        (Decode.field "releaseDate" Decode.string)
        (Decode.field "releaseStatus" releaseStatusDecoder)
        (Decode.field "releasedByName" Decode.string)
        (Decode.field "customers" (Decode.list customerDetailDecoder))
        |> Decode.andThen (\fn -> Decode.map fn (Decode.field "notes" (Decode.list noteDetailDecoder)))


-- CREATE VERSION REQUEST


type alias CreateVersionRequest =
    { version : String
    , softwareId : Int
    , releaseDate : String
    , releaseStatus : ReleaseStatus
    , customerIds : List Int
    , customerStages : List CustomerStageInput
    , notes : List NoteInput
    , preReleaseBy : Maybe Int
    , preReleaseDate : Maybe String
    , releasedBy : Maybe Int
    , releasedDate : Maybe String
    , productionReadyBy : Maybe Int
    , productionReadyDate : Maybe String
    }


type alias NoteInput =
    { note : String
    , customerIds : List Int
    }


type alias CustomerStageInput =
    { customerId : Int
    , releaseStage : CustomerReleaseStage
    }


createVersionEncoder : CreateVersionRequest -> Encode.Value
createVersionEncoder data =
    Encode.object
        [ ( "version", Encode.string data.version )
        , ( "softwareId", Encode.int data.softwareId )
        , ( "releaseDate", Encode.string data.releaseDate )
        , ( "releaseStatus", Encode.string (releaseStatusToString data.releaseStatus) )
        , ( "customerIds", Encode.list Encode.int data.customerIds )
        , ( "customerStages", Encode.list customerStageInputEncoder data.customerStages )
        , ( "notes", Encode.list noteInputEncoder data.notes )
        , ( "preReleaseBy", Maybe.withDefault Encode.null (Maybe.map Encode.int data.preReleaseBy) )
        , ( "preReleaseDate", Maybe.withDefault Encode.null (Maybe.map Encode.string data.preReleaseDate) )
        , ( "releasedBy", Maybe.withDefault Encode.null (Maybe.map Encode.int data.releasedBy) )
        , ( "releasedDate", Maybe.withDefault Encode.null (Maybe.map Encode.string data.releasedDate) )
        , ( "productionReadyBy", Maybe.withDefault Encode.null (Maybe.map Encode.int data.productionReadyBy) )
        , ( "productionReadyDate", Maybe.withDefault Encode.null (Maybe.map Encode.string data.productionReadyDate) )
        ]


noteInputEncoder : NoteInput -> Encode.Value
noteInputEncoder note =
    Encode.object
        [ ( "note", Encode.string note.note )
        , ( "customerIds", Encode.list Encode.int note.customerIds )
        ]


customerStageInputEncoder : CustomerStageInput -> Encode.Value
customerStageInputEncoder stage =
    Encode.object
        [ ( "customerId", Encode.int stage.customerId )
        , ( "releaseStage", Encode.string (customerReleaseStageToString stage.releaseStage) )
        ]


-- UPDATE VERSION REQUEST


type alias UpdateVersionRequest =
    { id : Int
    , releaseDate : String
    , releaseStatus : ReleaseStatus
    , customerIds : List Int
    , customerStages : List CustomerStageInput
    , notes : List UpdateNoteInput
    }


type alias UpdateNoteInput =
    { id : Maybe Int
    , note : String
    , customerIds : List Int
    }


updateVersionEncoder : UpdateVersionRequest -> Encode.Value
updateVersionEncoder data =
    Encode.object
        [ ( "id", Encode.int data.id )
        , ( "releaseDate", Encode.string data.releaseDate )
        , ( "releaseStatus", Encode.string (releaseStatusToString data.releaseStatus) )
        , ( "customerIds", Encode.list Encode.int data.customerIds )
        , ( "customerStages", Encode.list customerStageInputEncoder data.customerStages )
        , ( "notes", Encode.list updateNoteInputEncoder data.notes )
        ]


updateNoteInputEncoder : UpdateNoteInput -> Encode.Value
updateNoteInputEncoder note =
    Encode.object
        [ ( "id", Maybe.withDefault Encode.null (Maybe.map Encode.int note.id) )
        , ( "note", Encode.string note.note )
        , ( "customerIds", Encode.list Encode.int note.customerIds )
        ]

