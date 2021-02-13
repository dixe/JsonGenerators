module Types exposing (..)


type alias Name =
    String


type ValidType
    = TypeAlias Name GenericsAnnotation TypeAnnotation
    | CustomType Name GenericsAnnotation Constructor (List Constructor)


type alias GenericsAnnotation =
    List String


type alias Constructor =
    { name : String
    , arguments : List TypeAnnotation
    }


type TypeAnnotation
    = Record RecordDefinition
    | Typed TypeDef
    | Tuple (List TypeAnnotation)


type TypeDef
    = Type Name (List TypeAnnotation)
    | ListDef TypeAnnotation
    | MaybeDef TypeAnnotation
    | DictDef TypeAnnotation TypeAnnotation
    | ResultDef TypeAnnotation TypeAnnotation


type alias RecordDefinition =
    List { name : String, anno : TypeAnnotation }