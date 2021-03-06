module ElmParser exposing (parse)

import DeadEndsToString exposing (deadEndsToString)
import Elm.Parser as Parser
import Elm.Processing
import Elm.Syntax.Declaration as Declaration
import Elm.Syntax.File
import Elm.Syntax.Node as Node
import Elm.Syntax.Type
import Elm.Syntax.TypeAlias as Tal
import Elm.Syntax.TypeAnnotation as Tan
import Parser as BaseParser
import Types exposing (..)


type Error
    = NotSupported String
    | Other String


type alias Model =
    Result Error (List ValidType)


type alias ParseResult a =
    Result (List Error) a


parse : String -> Result String (List ValidType)
parse input =
    case Parser.parse input of
        Ok p ->
            case getDeclarations <| Elm.Processing.process Elm.Processing.init p of
                Ok types ->
                    Ok types

                Err err ->
                    Err <| String.join "\n" <| List.map errorToString err

        Err errs ->
            Err <| deadEndsToString errs


errorToString : Error -> String
errorToString e =
    case e of
        NotSupported s ->
            "NotSupported: " ++ s

        Other s ->
            "Error: " ++ s


getDeclarations : Elm.Syntax.File.File -> ParseResult (List ValidType)
getDeclarations file =
    flattenParseResults <| List.map getDeclaration file.declarations


getDeclaration : Node.Node Declaration.Declaration -> ParseResult ValidType
getDeclaration node =
    case Node.value node of
        Declaration.AliasDeclaration al ->
            getAlias al

        Declaration.CustomTypeDeclaration c ->
            getType c

        n ->
            Err [ NotSupported "Only Type and Type alias is supported" ]


getConstructor : Elm.Syntax.Type.ValueConstructor -> ParseResult Constructor
getConstructor vc =
    let
        pArgs =
            flattenParseResults <| List.map (\a -> argument <| Node.value a) <| vc.arguments
    in
    case pArgs of
        Ok args ->
            Ok
                { name = Node.value vc.name
                , arguments = args
                }

        Err e ->
            Err e


argument : Tan.TypeAnnotation -> ParseResult TypeAnnotation
argument vs =
    typeAnnotation vs


getType : Elm.Syntax.Type.Type -> ParseResult ValidType
getType t =
    let
        consts : ParseResult (List Constructor)
        consts =
            flattenParseResults <|
                List.map
                    (\x -> getConstructor <| Node.value x)
                    t.constructors

        generics =
            List.map Node.value t.generics
    in
    case consts of
        Ok pcs ->
            case pcs of
                [] ->
                    Err [ Other "No custom type constructors" ]

                c :: cs ->
                    Ok <| CustomType (Node.value t.name) generics c cs

        Err es ->
            Err es


getAlias : Tal.TypeAlias -> ParseResult ValidType
getAlias ta =
    case typeAnnotation <| Node.value ta.typeAnnotation of
        Ok anno ->
            Ok <| TypeAlias (Node.value ta.name) (List.map Node.value ta.generics) anno

        Err n ->
            Err n


typeAnnotation : Tan.TypeAnnotation -> ParseResult TypeAnnotation
typeAnnotation anno =
    let
        withOneArg : String -> (TypeAnnotation -> TypeDef) -> List TypeAnnotation -> ParseResult TypeAnnotation
        withOneArg typeName toTypeDef args =
            case args of
                a :: [] ->
                    Ok <| Typed <| toTypeDef a

                _ ->
                    Err <| List.map Other [ typeName ++ " with " ++ (String.fromInt <| List.length args) ++ " arguments" ]
    in
    case anno of
        Tan.Record r ->
            map Record (getFields r)

        Tan.Typed mod arguments ->
            let
                ( _, name ) =
                    Node.value mod

                parsedArgs : ParseResult (List TypeAnnotation)
                parsedArgs =
                    flattenParseResults <| List.map (\x -> x |> Node.value |> typeAnnotation) arguments
            in
            mapPr
                (\args ->
                    case name of
                        -- handle builtins like lists
                        "List" ->
                            withOneArg "List" ListDef args

                        "Maybe" ->
                            withOneArg "List" MaybeDef args

                        "Dict" ->
                            case args of
                                a :: b :: [] ->
                                    Ok <| Typed <| DictDef a b

                                _ ->
                                    Err <| List.map Other [ "Dict with " ++ (String.fromInt <| List.length args) ++ " arguments" ]

                        "Result" ->
                            case args of
                                a :: b :: [] ->
                                    Ok <| Typed <| ResultDef a b

                                _ ->
                                    Err <| List.map Other [ "Result with " ++ (String.fromInt <| List.length args) ++ " arguments" ]

                        n ->
                            Ok <| Typed <| Type (baseType n) args
                )
                parsedArgs

        Tan.Tupled arguments ->
            let
                parsedArgs =
                    flattenParseResults <| List.map (\x -> x |> Node.value |> typeAnnotation) arguments
            in
            map Tuple parsedArgs

        Tan.GenericType t ->
            Ok <| Typed <| Type (baseType t) []

        Tan.Unit ->
            Err <| [ NotSupported "Unit" ]

        Tan.GenericRecord _ _ ->
            Err <| [ NotSupported "GeneriRecord" ]

        Tan.FunctionTypeAnnotation _ _ ->
            Err <| [ NotSupported "Functions" ]


baseType : String -> BaseType
baseType t =
    case t of
        "String" ->
            TString

        "Int" ->
            TInt

        "Float" ->
            TFloat

        n ->
            TOther n


getFields : Tan.RecordDefinition -> ParseResult RecordDefinition
getFields rec =
    let
        rs =
            List.map (\n -> Node.value n) rec

        ls : ParseResult RecordDefinition
        ls =
            flattenParseResults <|
                List.map
                    (\( n, t ) ->
                        case typeAnnotation <| Node.value t of
                            Ok anno ->
                                Ok { name = Node.value n, anno = anno }

                            Err e ->
                                Err e
                    )
                    rs
    in
    ls



-- ParseResult HELPERS


flattenParseResults : List (ParseResult a) -> ParseResult (List a)
flattenParseResults prs =
    case prs of
        [] ->
            Ok []

        p :: pr ->
            combine p <| flattenParseResults pr


combine : ParseResult a -> ParseResult (List a) -> ParseResult (List a)
combine pr prs =
    case ( pr, prs ) of
        ( Ok a, Ok al ) ->
            Ok (a :: al)

        ( Err e, Ok _ ) ->
            Err e

        ( Ok _, Err e ) ->
            Err e

        ( Err e1, Err e2 ) ->
            Err (e1 ++ e2)


map : (a -> b) -> ParseResult a -> ParseResult b
map f r =
    case r of
        Ok a ->
            Ok <| f a

        Err e ->
            Err e


mapPr : (a -> ParseResult b) -> ParseResult a -> ParseResult b
mapPr f r =
    case r of
        Ok a ->
            f a

        Err e ->
            Err e
