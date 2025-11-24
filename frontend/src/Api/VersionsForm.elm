module Api.VersionsForm exposing (CountryGroup, Model, NoteForm, countryGroups, filterCountryGroups, filterCustomers, countryDisplayLabel, latestCountryVersionStatus, LatestVersionStatus, ensureVersionDetails, versionsForSelectedSoftware, versionHasCountry)

import Api.Data exposing (Customer, ReleaseStatus, Version, VersionDetail)
import Dict
import Effect exposing (Effect)


-- TYPES


type alias Model =
    { version : String
    , softwareId : Int
    , releaseDate : String
    , releaseTime : String
    , releaseStatus : ReleaseStatus
    , selectedCustomers : List Int
    , notes : List NoteForm
    , countryFilter : String
    , customerFilter : String
    , versions : List Version
    , versionsLoading : Bool
    , versionDetails : Dict.Dict Int VersionDetail
    , loadingVersionDetailIds : List Int
    }


type alias CountryGroup =
    { id : Int
    , name : String
    , customerIds : List Int
    }


type alias NoteForm =
    { note : String
    , customerIds : List Int
    , id : Maybe Int
    }


type LatestVersionStatus
    = LatestVersionFound String String
    | LatestVersionLoading
    | LatestVersionNone


-- HELPER FUNCTIONS


countryGroups : List Customer -> List CountryGroup
countryGroups customers =
    customers
        |> List.foldl
            (\customer acc ->
                Dict.update customer.country.id
                    (\maybeGroup ->
                        case maybeGroup of
                            Just group ->
                                Just { group | customerIds = customer.id :: group.customerIds }

                            Nothing ->
                                Just
                                    { id = customer.country.id
                                    , name = customer.country.name
                                    , customerIds = [ customer.id ]
                                    }
                    )
                    acc
            )
            Dict.empty
        |> Dict.values
        |> List.map (\group -> { group | customerIds = List.reverse group.customerIds })
        |> List.sortBy .name


filterCountryGroups : String -> Model -> List CountryGroup -> List CountryGroup
filterCountryGroups query model groups =
    let
        trimmed =
            String.toLower (String.trim query)
    in
    if String.isEmpty trimmed then
        groups

    else
        List.filter
            (\group ->
                let
                    labelText =
                        String.toLower (countryDisplayLabel model group)
                in
                String.contains trimmed labelText
                    || String.contains trimmed (String.toLower group.name)
            )
            groups


filterCustomers : String -> List Customer -> List Customer
filterCustomers query customers =
    let
        trimmed =
            String.toLower (String.trim query)
    in
    if String.isEmpty trimmed then
        customers

    else
        List.filter
            (\customer ->
                String.contains trimmed (String.toLower customer.name)
                    || String.contains trimmed (String.toLower customer.country.name)
            )
            customers


countryDisplayLabel : Model -> CountryGroup -> String
countryDisplayLabel model country =
    country.name ++ countryLatestSuffix model country


countryLatestSuffix : Model -> CountryGroup -> String
countryLatestSuffix model country =
    case latestCountryVersionStatus model country of
        LatestVersionFound versionStr _ ->
            " [" ++ versionStr ++ "]"

        LatestVersionLoading ->
            " – Loading latest release..."

        LatestVersionNone ->
            ""


latestCountryVersionStatus : Model -> CountryGroup -> LatestVersionStatus
latestCountryVersionStatus model country =
    if model.softwareId == 0 then
        LatestVersionNone

    else
        let
            relevantVersions =
                versionsForSelectedSoftware model

            findLatest versions =
                case versions of
                    [] ->
                        LatestVersionNone

                    v :: rest ->
                        case Dict.get v.id model.versionDetails of
                            Just detail ->
                                if versionHasCountry detail country then
                                    LatestVersionFound v.version v.releaseDate

                                else
                                    findLatest rest

                            Nothing ->
                                if List.member v.id model.loadingVersionDetailIds then
                                    LatestVersionLoading

                                else
                                    findLatest rest
        in
        if List.isEmpty relevantVersions then
            if model.versionsLoading then
                LatestVersionLoading

            else
                LatestVersionNone

        else
            findLatest relevantVersions


versionHasCountry : VersionDetail -> CountryGroup -> Bool
versionHasCountry detail country =
    detail.customers
        |> List.any
            (\customer ->
                String.toLower customer.countryName
                    == String.toLower country.name
            )


versionsForSelectedSoftware : Model -> List Version
versionsForSelectedSoftware model =
    model.versions
        |> List.filter (\v -> v.softwareId == model.softwareId)


ensureVersionDetails : Model -> (Int -> Effect msg) -> ( Model, Effect msg )
ensureVersionDetails model fetchVersionDetailCmd =
    if model.softwareId == 0 then
        ( model, Effect.none )

    else
        let
            versionIds =
                versionsForSelectedSoftware model
                    |> List.map .id

            idsToFetch =
                versionIds
                    |> List.filter
                        (\vid ->
                            (not (Dict.member vid model.versionDetails))
                                && (not (List.member vid model.loadingVersionDetailIds))
                        )
        in
        if List.isEmpty idsToFetch then
            ( model, Effect.none )

        else
            let
                newLoading =
                    idsToFetch
                        |> List.foldl
                            (\vid acc ->
                                if List.member vid acc then
                                    acc

                                else
                                    vid :: acc
                            )
                            model.loadingVersionDetailIds

                effects =
                    idsToFetch
                        |> List.map fetchVersionDetailCmd
            in
            ( { model | loadingVersionDetailIds = newLoading }
            , Effect.batch effects
            )



