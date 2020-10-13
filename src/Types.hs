module Types where

import Text.Printf
import Data.List (intercalate)

data VariableName = InstanceVar String | ClassVar String | SimpleVar String deriving (Show)

simpleVarName :: VariableName -> String
simpleVarName x = case x of
    InstanceVar s -> s
    ClassVar s -> s
    SimpleVar s -> s

varName :: VariableName -> String
varName x = case x of
    InstanceVar str -> "$this->" ++ str
    ClassVar str -> "static::$" ++ str
    SimpleVar str -> "$" ++ str

data FunctionBody = OneLine Salty -- e.g. incr x := x + 1
                      | Block [Salty] -- fib x := do if x < 2 .... end
                      | LambdaFunction { -- \a b -> a + b
                        lArguments :: [String],
                        lBody :: Salty
                      }
                      | AmpersandFunction VariableName -- &:@function (used for maps/each etc)
                      deriving (Show)

data AssignmentType = Equals | PlusEquals | MinusEquals | OrEquals deriving (Show)

-- function args
data Argument = Argument {
                  argType :: Maybe String,
                  argName :: String,
                  argDefault :: Maybe String
                } deriving (Show)

argWithDefaults name = Argument Nothing name Nothing

data HigherOrderFunction = Each | Map | Select | Any | All deriving (Show)

data Salty = Assignment { -- e.g. a = 1 / a += 1 / a ||= 0
               aName :: VariableName,
               aAssignmentType :: AssignmentType,
               aValue :: Salty
             }
             | Function {
               fName :: VariableName,
               fArguments :: [Argument],
               fBody :: FunctionBody
             }
             | SaltyNumber String
             | SaltyString String
             | FunctionCall { -- e.g. obj.foo / obj.foo(1) / foo(1, 2)
               fObject :: Maybe VariableName,
               fCallName :: VariableName,
               fCallArguments :: [String]
             }
             | HigherOrderFunctionCall { -- higher order function call. I'm adding support for a few functions like map/filter/each
               hoObject :: VariableName,
               hoCallName :: HigherOrderFunction,
               hoFunction :: FunctionBody  --  either lambda or ampersand function.
             }
             -- | TypeDefinition { -- e.g. foo :: String, String -> Num. tTypes would be ["String", "String", "Num"]
             --   tName :: String,
             --   tTypes :: [String]
             -- }
             -- | FeatureFlag String
             -- | ExistenceCheck { -- e.g. "hash ? key" gets converted to "isset($hash[$key])"
             --   eHash :: VariableName,
             --   eKey :: VariableName
             -- }
             | HashLookup { -- e.g. "hash > key" -> "$hash[$key]"
               eHash :: Either VariableName Salty,
               eKey :: VariableName
             }
             -- | FMapCall {
             --   fmapObject :: Salty,
             --   fmapFunction :: FunctionBody
             -- }
             | ReturnStatement Salty
             | PhpLine String
             | Salt
             deriving (Show)


class ConvertToPhp a where
    toPhp :: a -> String

instance ConvertToPhp VariableName where
  toPhp (InstanceVar s) = "$this->" ++ s
  toPhp (ClassVar s) = "self::$" ++ s
  toPhp (SimpleVar s) = '$':s

instance ConvertToPhp FunctionBody where
  toPhp (OneLine r@(ReturnStatement s)) = toPhp r
  toPhp (OneLine r@(PhpLine s)) = s
  toPhp (OneLine s) = "return " ++ (toPhp s) ++ ";"
  toPhp (Block s) = (intercalate ";\n" $ map toPhp s) ++ ";"
  toPhp (LambdaFunction args body) = (unlines $ map (printf "$%s = null;\n") args) ++ toPhp body
  toPhp (AmpersandFunction (SimpleVar str)) = printf "%s($i)" str
  toPhp (AmpersandFunction (InstanceVar str)) = printf "$i->%s()" str

instance ConvertToPhp Argument where
  toPhp (Argument (Just typ) name (Just default_)) = printf "?%s $%s = %s" typ name default_
  toPhp (Argument (Just typ) name Nothing) = typ ++ " $" ++ name
  toPhp (Argument Nothing name (Just default_)) = printf "$%s = %s" name default_
  toPhp (Argument Nothing name Nothing) = "$" ++ name

instance ConvertToPhp Salty where
  toPhp (Assignment name Equals value) = (toPhp name) ++ " = " ++ (toPhp value)
  toPhp (Assignment name PlusEquals value) = printf "%s = %s + %s" n n (toPhp value)
    where n = toPhp name
  toPhp (Assignment name MinusEquals value) = printf "%s = %s - %s" n n (toPhp value)
    where n = toPhp name
  toPhp (Assignment name OrEquals value) = printf "%s = %s ?? %s" n n (toPhp value)
    where n = toPhp name

  toPhp (Function name args (LambdaFunction _ _)) = "lambda function body not allowed as method body " ++ (show name)
  toPhp (Function name args (AmpersandFunction _)) = "ampersand function body not allowed as method body " ++ (show name)
  toPhp (Function name args body) = printf "%s(%s) {\n%s\n}" funcName funcArgs (toPhp body)
    where funcName = case name of
            InstanceVar str -> "function " ++ str
            ClassVar str -> "static function " ++ str
            SimpleVar str -> "function " ++ str
          funcArgs = intercalate ", " $ map toPhp args

  toPhp (SaltyNumber s) = s
  toPhp (SaltyString s) = s

  toPhp (FunctionCall Nothing (SimpleVar str) args) = printf "%s(%s)" str (intercalate ", " args)
  toPhp (FunctionCall Nothing (InstanceVar str) args) = printf "$this->%s(%s)" str (intercalate ", " args)
  toPhp (FunctionCall Nothing (ClassVar str) args) = printf "static::%s(%s)" str (intercalate ", " args)
  toPhp (FunctionCall (Just (SimpleVar obj)) funcName args) = printf "$%s->%s(%s)" obj (simpleVarName funcName) (intercalate ", " args)
  toPhp (FunctionCall (Just (InstanceVar obj)) funcName args) = printf "$this->%s->%s(%s)" obj (simpleVarName funcName) (intercalate ", " args)
  toPhp (FunctionCall (Just (ClassVar obj)) funcName args) = printf "static::%s->%s(%s)" obj (simpleVarName funcName) (intercalate ", " args)

  -- each
  toPhp (HigherOrderFunctionCall obj Each (LambdaFunction (loopVar:xs) body)) =
                printf "foreach (%s as $%s) {\n%s;\n}" (varName obj) loopVar (toPhp body)

  toPhp (HigherOrderFunctionCall obj Each af@(AmpersandFunction name)) =
                printf "foreach (%s as $i) {\n%s;\n}" (varName obj) (toPhp af)

  -- map
  toPhp (HigherOrderFunctionCall obj Map (LambdaFunction (loopVar:accVar:[]) body)) =
                printf "$%s = [];\nforeach (%s as $%s) {\n$%s []= %s;\n}" accVar (varName obj) loopVar accVar (toPhp body)

  toPhp (HigherOrderFunctionCall obj Map (LambdaFunction (loopVar:[]) body)) =
                printf "$%s = [];\nforeach (%s as $%s) {\n$%s []= %s;\n}" accVar (varName obj) loopVar accVar (toPhp body)
                  where accVar = "result"

  toPhp (HigherOrderFunctionCall obj Map af@(AmpersandFunction name)) =
                printf "$acc = [];\nforeach (%s as $i) {\n$acc []= %s;\n}" (varName obj) (toPhp af)

  -- select
  toPhp (HigherOrderFunctionCall obj Select (LambdaFunction (loopVar:accVar:[]) body)) =
                printf "$%s = [];\nforeach (%s as $%s) {\nif(%s) {\n$%s []= %s;\n}\n}" accVar (varName obj) loopVar (toPhp body) accVar loopVar
  toPhp (HigherOrderFunctionCall obj Select (LambdaFunction (loopVar:[]) body)) =
                printf "$%s = [];\nforeach (%s as $%s) {\nif(%s) {\n$%s []= %s;\n}\n}" accVar (varName obj) loopVar (toPhp body) accVar loopVar
                        where accVar = "result"
  toPhp (HigherOrderFunctionCall obj Select af@(AmpersandFunction name)) =
                printf "$acc = [];\nforeach (%s as $i) {\nif(%s) {\n$acc []= $i;\n}\n}" (varName obj) (toPhp af)

  -- any
  toPhp (HigherOrderFunctionCall obj Any (LambdaFunction (loopVar:xs) body)) =
                printf "$result = false;\nforeach (%s as $%s) {\nif(%s) {\n$result = true;\nbreak;\n}\n}" (varName obj) loopVar (toPhp body)
  toPhp (HigherOrderFunctionCall obj Any af@(AmpersandFunction name)) =
                printf "$result = false;\nforeach (%s as $i) {\nif(%s) {\n$result = true;\nbreak;\n}\n}" (varName obj) (toPhp af)

  -- all
  toPhp (HigherOrderFunctionCall obj All (LambdaFunction (loopVar:xs) body)) =
                printf "$result = true;\nforeach (%s as $%s) {\nif(!%s) {\n$result = false;\nbreak;\n}\n}" (varName obj) loopVar (toPhp body)
  toPhp (HigherOrderFunctionCall obj All af@(AmpersandFunction name)) =
                printf "$result = true;\nforeach (%s as $i) {\nif(!%s) {\n$result = false;\nbreak;\n}\n}" (varName obj) (toPhp af)

  toPhp (HashLookup (Left var) key) = printf "%s[%s]" (varName var) (varName key)
  toPhp (HashLookup (Right hashLookup_) key) = printf "%s[%s]" (toPhp hashLookup_) (varName key)
  toPhp Salt = "I'm salty"
  toPhp (ReturnStatement s) = "return " ++ (toPhp s) ++ ";"
  toPhp (PhpLine line) = line

  toPhp x = "not implemented yet: " ++ (show x)

--not implemented yet: HigherOrderFunctionCall {hoObject = InstanceVar "adit", hoCallName = Map, hoFunction = LambdaFunction {lArguments = ["x"], lBody = PhpLine "x + 1"}}
             -- | HigherOrderFunctionCall { -- higher order function call. I'm adding support for a few functions like map/filter/each
             --   hoObject :: VariableName,
             --   hoCallName :: HigherOrderCall,
             --   hoFunction :: FunctionBody  --  either lambda or ampersand function.
             -- }
             -- | HashLookup { -- e.g. "hash > key" -> "$hash[$key]"
             --   eHash :: Either VariableName HashLookup,
             --   eKey :: VariableName
             -- }
