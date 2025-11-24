module Api.Endpoint exposing (..)

import Url.Builder


baseUrl : String
baseUrl =
    "http://localhost:5000"


auth : List String -> String
auth paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "auth" :: paths) []


countries : List String -> String
countries paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "countries" :: paths) []


customers : List String -> String
customers paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "customers" :: paths) []


software : List String -> String
software paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "software" :: paths) []


users : List String -> String
users paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "users" :: paths) []


versions : List String -> String
versions paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "versions" :: paths) []


versionsLatest : Int -> Int -> String
versionsLatest softwareId customerId =
    Url.Builder.crossOrigin
        baseUrl
        [ "api", "versions", "latest" ]
        [ Url.Builder.int "softwareId" softwareId
        , Url.Builder.int "customerId" customerId
        ]


installerOpen : String
installerOpen =
    Url.Builder.crossOrigin baseUrl ("api" :: "installer" :: [ "open" ]) []


audit : List String -> String
audit paths =
    Url.Builder.crossOrigin baseUrl ("api" :: "audit" :: paths) []


