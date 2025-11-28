module Utils.NoteFormatter exposing (formatNote, formatNoteText)

{-| Module for formatting release notes with markdown-like syntax.

Supports:
- **text** for bold
- • for bullet points

-}

import Html exposing (Html, div, strong, text)
import Html.Attributes exposing (style)
import Regex


{-| Format a note string into HTML with proper formatting for bold text and bullet points.
-}
formatNote : String -> Html msg
formatNote noteText =
    let
        lines =
            String.split "\n" noteText

        formattedLines =
            List.map formatLine lines
    in
    div [] formattedLines


{-| Format a single line, handling bold text and preserving line breaks.
-}
formatLine : String -> Html msg
formatLine line =
    div [ style "margin-bottom" "0.25rem" ]
        (parseBoldText line)


{-| Parse bold text markers (**text**) and convert to HTML strong tags.
-}
parseBoldText : String -> List (Html msg)
parseBoldText input =
    let
        -- Regex to match **text**
        boldRegex =
            Regex.fromString "\\*\\*([^*]+)\\*\\*"
                |> Maybe.withDefault Regex.never
        
        matches =
            Regex.find boldRegex input
        
        -- Build HTML by splitting on matches
        result =
            buildHtmlFromMatches input matches 0
    in
    result


{-| Build HTML elements from regex matches.
-}
buildHtmlFromMatches : String -> List Regex.Match -> Int -> List (Html msg)
buildHtmlFromMatches input matches currentIndex =
    case matches of
        [] ->
            -- No more matches, add remaining text
            let
                remainingText =
                    String.dropLeft currentIndex input
            in
            if String.isEmpty remainingText then
                []
            else
                [ text remainingText ]
        
        match :: restMatches ->
            let
                -- Text before the match
                beforeText =
                    String.slice currentIndex match.index input
                
                -- The bold text (first capture group)
                boldText =
                    match.submatches
                        |> List.head
                        |> Maybe.withDefault Nothing
                        |> Maybe.withDefault ""
                
                -- Next index after this match
                nextIndex =
                    match.index + String.length match.match
                
                -- Build elements
                beforeElement =
                    if String.isEmpty beforeText then
                        []
                    else
                        [ text beforeText ]
                
                boldElement =
                    [ strong [ style "font-weight" "600" ] [ text boldText ] ]
                
                restElements =
                    buildHtmlFromMatches input restMatches nextIndex
            in
            beforeElement ++ boldElement ++ restElements


{-| Convert formatted note text to plain text for display in tables or simple contexts.
This removes formatting markers.
-}
formatNoteText : String -> String
formatNoteText noteText =
    noteText
        |> String.replace "**" ""

