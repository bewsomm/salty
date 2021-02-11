module Parser where

import Types
import Utils
import Formatting
import Text.Parsec
import Text.ParserCombinators.Parsec.Char
import Text.Parsec.Combinator
import Debug.Trace (trace)
import ToPhp

varNameChars = oneOf "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890_"
lambdaVarNameChars = oneOf "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_ "
classNameChars = oneOf "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890_\\"
functionArgsChars = oneOf "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890_&"
hashKeyChars = oneOf "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'\""
typeChars = oneOf "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_?[]"
constChars = oneOf "ABCDEFGHIJKLMNOPQRSTUVWXYZ_"

data SaltyState = SaltyState {
                      lastSalty :: Salty,
                      stateScopes :: [Scope]
                  }

type SaltyParser = Parsec String SaltyState Salty

debug :: String -> SaltyParser
debug str = return (SaltyString str)
-- debug str = parserTrace str >> return (SaltyString str)

saltyToPhp :: Int -> String -> String
saltyToPhp indentAmt str = case (build str) of
                   Left err -> show err
                   Right xs -> saltyToPhp_ indentAmt xs
                   -- Right xs -> checkForErrors str (saltyToPhp_ indentAmt xs)

numLines str = length . filter (/="") . lines $ str

checkForErrors inputStr outputStr = if (numLines outputStr) < (numLines inputStr)
                                  then outputStr ++ "\n// failed, possibly on:\n" ++ (findErrorLine inputStr)
                                  else outputStr

findErrorLine :: String -> String
findErrorLine str = findErrorLine_ ((map (removeSemicolons . strip)) . lines $ str)

findErrorLine_ :: [String] -> String
findErrorLine_ [] = "// no errors"
findErrorLine_ lines = case (build (head lines)) of
                         Left err -> "error from adit" -- this never gets hit, not sure why.
                         Right [] -> head lines -- this means the parse failed, so this is the issue line.
                         Right xs -> findErrorLine_ (tail lines) -- this means the parse succeeded, so try the next line.

saltyToDebugTree :: String -> String
saltyToDebugTree str = case (build str) of
                   Left err -> show err
                   Right xs -> formatDebug xs

saltyToDebugTreeCheckBackTracks :: String -> String
saltyToDebugTreeCheckBackTracks str = case (build str) of
                   Left err -> show err
                   Right xs -> formatDebugStripBackTracks xs


startingState = SaltyState EmptyLine []

-- <* eof operator will return what saltyParser parsed ... otherwise build would return `()`
-- which is what eof returns.
-- idea from https://stackoverflow.com/questions/16209278/parsec-consume-all-input
build :: String -> Either ParseError [Salty]
build str_ = runParser (saltyParser <* eof) startingState "saltyParser" str
  where str = unlines . (map (removeSemicolons . strip)) . lines $ str_

saltyParser :: Parsec String SaltyState [Salty]
saltyParser = debug "start" >> (many saltyParserSingle)

saltyParserSingle :: SaltyParser
saltyParserSingle = debug "saltyParserSingle" >> do
  salty <- saltyParserSingle_
  debug $ "checking for newline: " ++ (show salty)
  result <- optionMaybe $ char '\n'
  case result of
       Nothing -> return salty
       (Just s) -> do
          debug $ "found a newline!" ++ [s]
          return (WithNewLine salty)

saltyParserSingle_ :: SaltyParser
saltyParserSingle_ = do
  debug "saltyParserSingle_"
  salty <- saltyParserSingleWithoutNewline
  case salty of
       EmptyLine -> return ()
       (Operation left op right) -> modifyState (saveIt right)
       (MultiAssign vars right) -> modifyState (saveIt right)
       salty -> modifyState (saveIt salty)
  return salty

saveIt :: Salty -> SaltyState -> SaltyState
saveIt salty (SaltyState _ scopes) = SaltyState salty scopes

saltyParserSingleWithoutNewline :: SaltyParser
saltyParserSingleWithoutNewline = do
  parens
  <||> higherOrderFunctionCall
  <||> hashTable
  <||> array
  -- <||> emptyHash
  <||> (braces Nothing)
  <||> function
  <||> functionTypeSignature
  <||> lambda
  <||> multiAssign
  <||> plusplusAll
  <||> operation
  <||> partialOperation
  <||> saltyString
  <||> range
  <||> saltyNumber
  <||> returnStatement
  <||> functionCall
  <||> attrAccess
  <||> arraySlice
  <||> stringIndex
  <||> stringSlice
  <||> hashLookup
  <||> partialHashLookup
  <||> partialFunctionCall
  <||> partialAttrAccess
  <||> negateSalty
  <||> saltyComment
  <||> phpComment
  <||> purePhp
  <||> emptyLine
  <||> ifStatement
  <||> whileStatement
  <||> classDefinition
  <||> objectCreation
  <||> saltyBool
  <||> saltyNull
  <||> saltyKeyword
  <||> saltyMagicConstant
  <||> phpVar
  <||> saltyOptional
  <||> variable

validFuncArgTypes :: SaltyParser
validFuncArgTypes = debug "validFuncArgTypes" >> do
       parens
  <||> array
  <||> hashTable
  -- <||> emptyHash
  <||> operation
  <||> partialOperation
  <||> saltyString
  <||> range
  <||> saltyNumber
  <||> functionCall
  <||> attrAccess
  <||> arraySlice
  <||> stringIndex
  <||> stringSlice
  <||> hashLookup
  <||> partialHashLookup
  <||> partialFunctionCall
  <||> partialAttrAccess
  <||> negateSalty
  <||> objectCreation
  <||> saltyBool
  <||> saltyNull
  <||> saltyMagicConstant
  <||> phpVar
  <||> purePhp
  <||> saltyOptional
  <||> variable
  <?> "a valid function argument type"

safeHead [] = Nothing
safeHead (x:xs) = Just x

variable = debug "variable" >> do
  name <- variableName
  scope_ <- (safeHead . stateScopes) <$> getState
  let scope = case scope_ of
       Just scope -> scope
       Nothing -> GlobalScope
  case isConstant (getVarName name) of
       True -> return $ Constant $ Variable name scope
       False -> return $ Variable name scope

variableName = debug "variableName" >> do
        staticVar
  <||>  instanceVar
  <||>  classVar
  <||>  simpleVar
  <?> "a variable"

parens = debug "parens" >> do
  char '('
  body <- saltyParser
  char ')'
  debug $ "parens done with: " ++ (show body)
  return $ Parens body

validHashValue = debug "validHashValue" >> do
       saltyString
  <||> saltyNumber
  <||> hashLookup
  <||> hashTable
  <||> array
  -- <||> emptyHash
  <||> saltyBool
  <||> saltyNull
  <||> saltyMagicConstant
  <||> purePhp
  <||> variable
  <?> "a valid hash value"

stringKey = debug "stringKey" >> do
  key <- many1 hashKeyChars
  return $ SaltyString key

saltyKey = debug "saltyKey" >> do
  char '['
  value <- hashLookup <||> saltyBool <||> saltyNull <||> purePhp <||> variable
  char ']'
  return value

keyValuePair = debug "keyValuePair" >> do
  key <- saltyKey <||> stringKey
  optional space
  char ':'
  space
  value <- validHashValue
  char ',' <||> char '}' <||> char '\n' <||> char ' '
  optional (oneOf " \n")
  return (key, value)

hashTable = debug "hashTable" >> do
  char '{'
  optional (oneOf " \n")
  kvPairs <- many1 keyValuePair
  optional $ char '}'
  return $ HashTable kvPairs

arrayValue = debug "arrayValue" >> do
  value <- validHashValue
  char ',' <||> char ']'
  optional space
  return value

array = debug "array" >> do
  char '['
  optional $ char '\n'
  salties <- many arrayValue
  optional $ char '\n'
  optional $ char ']'
  return $ Array salties

emptyHash = debug "emptyHash" >> do
  char '{'
  many $ char ' '
  char '}'
  return $ Array []

addScope :: Scope -> SaltyState -> SaltyState
addScope scope (SaltyState prev scopes) = SaltyState prev (scope:scopes)

popScope :: SaltyState -> SaltyState
popScope (SaltyState prev (s:scopes)) = SaltyState prev scopes

braces :: Maybe Scope -> SaltyParser
braces scope_ = debug "braces" >> do
  char '{'
  optional space
  case scope_ of
       Just scope -> modifyState (addScope scope)
       Nothing -> return ()
  body <- saltyParser
  optional space
  case scope_ of
       Just scope -> modifyState popScope
       Nothing -> return ()
  char '}'
  debug $ "braces done with: " ++ (show body)
  return $ Braces body

function = debug "function" >> do
  multilineFunction <||> guardFunction <||> onelineFunction

varArg = debug "varArg" >> do
  string "..."
  arg <- many1 functionArgsChars
  return $ "..." ++ arg

functionArgs = debug "functionArgs" >> many (do
  arg <- varArg <||> many1 functionArgsChars
  space
  return arg)

makeArgNames :: [String] -> [ArgumentName]
makeArgNames [] = []
makeArgNames (arg:rest)
  | arg == "" = [ArgumentName "missing arg" False]
  | head arg == '&' = (ArgumentName (tail arg) True):(makeArgNames rest)
  | otherwise       = (ArgumentName arg False):(makeArgNames rest)

getOrDefaultScope (Just x) = x
getOrDefaultScope Nothing = GlobalScope

bar = debug "foo" >> do
  body <- saltyParser
  return body

saltyNewline = debug "saltyNewline" >> do
  char '\n'
  return Salt

saltyEOF = debug "saltyEOF" >> do
  eof
  return Salt

wrapInSalt parser = debug "wrapInSalt" >> do
  parser
  return Salt

parseTill endParser = debug "parseTill" >> do
  body <- manyTill saltyParserSingle_ (try (endParser <||> saltyEOF))
  return body

onelineFunction = debug "onelineFunction" >> do
  prevSalty <- lastSalty <$> getState
  scope <- (getOrDefaultScope . safeHead . stateScopes) <$> getState
  (name, visibility) <- getVisibility <$> variableName
  space
  _args <- functionArgs
  let args = makeArgNames _args
  string ":="
  space
  modifyState (addScope FunctionScope)
  body <- parseTill saltyNewline
  wheres <- many whereClause
  modifyState popScope
  case prevSalty of
       FunctionTypeSignature _ types ->
          return $ Function name (argWithTypes args types) (wheres ++ body) visibility scope
       _ ->
          return $ Function name (map argWithDefaults args) (wheres ++ body) visibility scope

multilineFunction = debug "multilineFunction" >> do
  prevSalty <- lastSalty <$> getState
  scope <- (getOrDefaultScope . safeHead . stateScopes) <$> getState
  (name, visibility) <- getVisibility <$> variableName
  space
  _args <- functionArgs
  let args = makeArgNames _args
  string ":="
  space
  body <- braces (Just FunctionScope)
  case prevSalty of
     FunctionTypeSignature _ types -> return $ Function name (argWithTypes args types) [body] visibility scope
     _ -> return $ Function name (map argWithDefaults args) [body] visibility scope

otherwiseGuard = do
  string "otherwise"
  return $ [SaltyString "otherwise"]

-- parseTillEndOfLine = debug "parseTillEndOfLine" >> do
--   body_ <- many1 (noneOf "\n")
--   optional $ char '\n'
--   case (build body_) of
--        Left err -> return $ [SaltyString (show err)]
--        Right body -> return body

guard = debug "guard" >> do
  char '|'
  space
  condition <- otherwiseGuard <||> (many1 validFuncArgTypes)
  optional $ string " -> "
  outcome <- parseTill saltyNewline
  return $ Guard condition outcome

whereClause = debug "whereClause" >> do
  string "where" <||> string "and"
  space
  op <- operation <||> multiAssign
  optional $ char '\n'
  return op

saltyGuard = debug "saltyGuard" >> do
  string "guard\n"
  guards <- many1 guard
  return $ SaltyGuard guards

guardFunction = debug "guardFunction" >> do
  prevSalty <- lastSalty <$> getState
  scope <- (getOrDefaultScope . safeHead . stateScopes) <$> getState
  (name, visibility) <- getVisibility <$> variableName
  space
  args <- makeArgNames <$> functionArgs
  string ":= "
  modifyState (addScope FunctionScope)
  guards <- saltyGuard
  wheres <- many whereClause
  let body = wheres ++ [guards]
  modifyState popScope
  case prevSalty of
     FunctionTypeSignature _ types -> return $ Function name (argWithTypes args types) body visibility scope
     _ -> return $ Function name (map argWithDefaults args) body visibility scope

argWithDefaults :: ArgumentName -> Argument
argWithDefaults name = Argument Nothing name Nothing

argWithTypes :: [ArgumentName] -> [ArgumentType] -> [Argument]
argWithTypes [] _ = []
argWithTypes (a:args) [] = (Argument Nothing a Nothing):(argWithTypes args [])
argWithTypes (a:args) (t:types) = (Argument (Just t) a Nothing):(argWithTypes args types)

getVisibility :: VariableName  -> (VariableName, Visibility)
getVisibility (InstanceVar name) = ((InstanceVar newName), visibility)
  where (visibility, newName) = _getVisibility name
getVisibility (StaticVar name) = ((StaticVar newName), visibility)
  where (visibility, newName) = _getVisibility name
getVisibility (ClassVar name) = ((ClassVar newName), visibility)
  where (visibility, newName) = _getVisibility name
getVisibility (SimpleVar name) = ((SimpleVar newName), visibility)
  where (visibility, newName) = _getVisibility name

_getVisibility :: String -> (Visibility, String)
_getVisibility "__construct" = (Public, "__construct")
_getVisibility ('_':xs) = (Private, xs)
_getVisibility str = (Public, str)

getVarName :: VariableName -> String
getVarName (InstanceVar str) = str
getVarName (StaticVar str) = str
getVarName (ClassVar str) = str
getVarName (SimpleVar str) = str

findArgTypes = debug "findArgTypes" >> do
  args <- many1 $ do
            typ <- many1 typeChars
            optional $ string " -> "
            if (last typ == '?')
               then return (ArgumentType True (init typ) False)
               else return (ArgumentType False typ False)
  return $ (init args) ++ [setToReturnArgType (last args)]

setToReturnArgType (ArgumentType o a _) = ArgumentType o a True

functionTypeSignature = debug "functionTypeSignature" >> do
  name <- variableName
  space
  string "::"
  space
  argTypes <- findArgTypes
  return $ FunctionTypeSignature name argTypes

operator = debug "operator" >> do
       (string "!=" >> return NotEquals)
  <||> (string "+=" >> return PlusEquals)
  <||> (string "-=" >> return MinusEquals)
  <||> (string "/=" >> return DivideEquals)
  <||> (string "*=" >> return MultiplyEquals)
  <||> (string "[]=" >> return ArrayPush)
  <||> (string "||=" >> return OrEquals)
  <||> (string "||" >> return OrOr)
  <||> (string "&&" >> return AndAnd)
  <||> (string "??" >> return NullCoalesce)
  <||> (string "++" >> return PlusPlus)
  <||> (string "<>" >> return ArrayMerge)
  <||> (string "<->" >> return ArrayDiff)
  <||> (string "instanceof" >> return InstanceOf)
  <||> (string "isa" >> return InstanceOf)
  <||> (string "in" >> return In)
  <||> (string "keyin" >> return KeyIn)
  <||> (string "==" >> return EqualsEquals)
  <||> (string "<=>" >> return Spaceship)
  <||> (string "<=" >> return LessThanOrEqualTo)
  <||> (string ">=" >> return GreaterThanOrEqualTo)
  <||> (string "<" >> return LessThan)
  <||> (string ">" >> return GreaterThan)
  <||> (string "+" >> return Add)
  <||> (string "-" >> return Subtract)
  <||> (string "/" >> return Divide)
  <||> (string "*" >> return Multiply)
  <||> (string "=" >> return Equals)
  <||> (string "%" >> return Modulo)
  <?> "an operator"

atom = debug "atom" >> do
       functionCall
  <||> attrAccess
  <||> arraySlice
  <||> stringIndex
  <||> stringSlice
  <||> hashLookup
  <||> saltyBool
  <||> saltyNull
  <||> saltyMagicConstant
  <||> variable
  <||> saltyString
  <||> saltyNumber
  <?> "an atom"

operation = debug "operation" >> do
  left <- atom
  space
  op <- operator
  space
  right <- saltyParserSingle_
  return $ Operation left op right

partialOperation = debug "partialOperation" >> do
  leftHandSide <- lastSalty <$> getState
  space
  op <- operator
  space
  right <- saltyParserSingle_
  return $ BackTrack (Operation leftHandSide op right)

partialAttrAccess = debug "partialAttrAccess" >> do
  leftHandSide <- lastSalty <$> getState
  char '.'
  attrName <- many1 varNameChars
  return $ BackTrack (AttrAccess leftHandSide attrName)

partialFunctionCall = debug "partialFunctionCall" >> do
  leftHandSide <- lastSalty <$> getState

  char '.'
  funcName <- many1 varNameChars
  char '('
  funcArgs <- findArgs
  char ')'

  return $ case leftHandSide of
             Operation l op r -> BackTrack $ Operation l op (FunctionCall (Just r) (Right (SimpleVar funcName)) funcArgs)
             _ -> BackTrack $ FunctionCall (Just leftHandSide) (Right (SimpleVar funcName)) funcArgs

negateSalty = debug "negateSalty" >> do
  char '!'
  s <- saltyParserSingle_
  return $ Negate s

emptyLine = debug "emptyLine" >> do
  string "\n"
  return EmptyLine

saltyString = debug "saltyString" >> do
  quoteType <- oneOf "'\""
  str <- many $ noneOf [quoteType]
  char quoteType
  return $ SaltyString str

saltyNumber = debug "saltyNumber" >> do
       decimal
  <||> integer
  <?> "a decimal or integer"

integer = debug "integer" >> do
  head <- oneOf "1234567890-"
  number <- many (oneOf "1234567890")
  return $ SaltyNumber (head:number)

decimal = debug "decimal" >> do
  head <- oneOf "1234567890-"
  number <- many (oneOf "1234567890")
  char '.'
  decimal <- many1 (oneOf "1234567890")
  return $ SaltyNumber ((head:number) ++ "." ++ decimal)

-- @foo
instanceVar = debug "instanceVar" >> do
  char '@'
  variable <- many1 varNameChars
  return $ InstanceVar variable

-- @@foo
staticVar = debug "staticVar" >> do
  string "@@"
  variable <- many1 varNameChars
  return $ StaticVar variable

-- foo
simpleVar = debug "simpleVar" >> do
  first <- (letter <||> char '_')
  rest <- many varNameChars
  return $ SimpleVar (first:rest)

classVar = debug "classVar" >> do
  classicClassVar <||> selfClassVar

selfClassVar = debug "selfClassVar" >> do
  string "self"
  return $ ClassVar "self"

classicClassVar = debug "classicClassVar" >> do
  start <- upper
  variable <- many1 classNameChars
  return $ ClassVar (start:variable)

higherOrderFunctionCall = debug "higherOrderFunctionCall" >> do
  optional $ char '('
  obj <- range <||> functionCall <||> partialFunctionCall <||> array <||> arraySlice <||> stringSlice <||> saltyOptional <||> variable
  optional $ char ')'
  char '.'
  funcName <-      (string "map" >> return Map)
              <||> (string "each" >> return Each)
              <||> (string "select" >> return Select)
              <||> (string "any" >> return Any)
              <||> (string "all" >> return All)
  char '('
  func <- lambda
  char ')'
  return $ HigherOrderFunctionCall obj funcName func "$result"

lambda = debug "lambda" >> do
  optional $ char '\\'
  args <-  many1 lambdaVarNameChars
  string "-> "
  body <- (braces Nothing) <||> saltyParserSingle_ <?> "a lambda function body"
  return $ LambdaFunction (words args) body

returnStatement = debug "returnStatement" >> do
  string "return "
  salty <- many1 saltyParserSingle_
  optional $ char '\n'
  return $ ReturnStatement (Braces salty)

saltyComment = do
  optional space
  char '#'
  line <- many1 $ noneOf "\n"
  string "\n"
  return $ SaltyComment line

phpComment = (do
  optional space
  string "//" <?> "a php comment"
  line <- many1 $ noneOf "\n"
  string "\n"
  return $ PhpComment line) <?> "a php comment"

purePhp = do
  string "`"
  line <- many1 $ noneOf "`"
  string "`"
  return $ PurePhp line

functionCall = debug "functionCall" >> do
       functionCallOnObject
  <||> functionCallWithoutObject
  <||> functionCallOnObjectWithoutParens
  <||> functionCallWithoutObjectWithoutParens
  <?> "a function call"

findArgs = debug "findArgs" >> do
  args <- many $ do
            s <- validFuncArgTypes
            optional $ char ','
            many space
            return s
  return args

attrAccess = debug "attrAccess" >> do
  obj <- saltyOptional <||> variable
  char '.'
  attrName <- many1 varNameChars
  return $ AttrAccess obj attrName

functionCallOnObject = debug "functionCallOnObject" >> do
  obj <- saltyOptional <||> variable
  char '.'
  funcName <- many1 varNameChars
  char '('
  funcArgs <- findArgs
  char ')'
  return $ FunctionCall (Just obj) (Right (SimpleVar funcName)) funcArgs

parseBuiltInFuncName :: VariableName -> Either BuiltInFunction VariableName
parseBuiltInFuncName (SimpleVar "p") = Left VarDumpShort
parseBuiltInFuncName s = Right s

functionCallWithoutObject = debug "functionCallWithoutObject" >> do
  funcName <- variableName
  char '('
  funcArgs <- findArgs
  char ')'
  return $ FunctionCall Nothing (parseBuiltInFuncName funcName) funcArgs

functionCallOnObjectWithoutParens = debug "functionCallOnObjectWithoutParens" >> do
  obj <- saltyOptional <||> variable
  char '.'
  funcName <- many1 varNameChars
  string " . " <||> string " $ "
  funcArgs <- functionCallOnObjectWithoutParens <||> functionCallWithoutObjectWithoutParens <||> validFuncArgTypes
  return $ FunctionCall (Just obj) (Right (SimpleVar funcName)) [funcArgs]

functionCallWithoutObjectWithoutParens = debug "functionCallWithoutObjectWithoutParens" >> do
  funcName <- variableName
  string " . " <||> string " $ "
  funcArgs <- functionCallOnObjectWithoutParens <||> functionCallWithoutObjectWithoutParens <||> validFuncArgTypes
  return $ FunctionCall Nothing (parseBuiltInFuncName funcName) [funcArgs]

arraySlice = debug "arraySlice" >> do
  array <- variable
  char '['
  start_ <- (Just <$> saltyParserSingle_) <||> nothing
  char ':'
  end <- (Just <$> saltyParserSingle_) <||> nothing
  char ']'
  let start = case start_ of
                Just salty -> salty
                Nothing -> SaltyNumber "0"
  return $ ArraySlice array start end

stringSlice = debug "stringSlice" >> do
  string <- variable
  char '<'
  start_ <- (Just <$> saltyParserSingle_) <||> nothing
  char ':'
  end <- (Just <$> saltyParserSingle_) <||> nothing
  char '>'
  let start = case start_ of
                Just salty -> salty
                Nothing -> SaltyNumber "0"
  return $ StringSlice string start end

stringIndex = debug "stringIndex" >> do
  string <- variable
  char '<'
  index <- saltyParserSingle_
  char '>'
  return $ StringIndex string index

hashLookup = debug "hashLookup" >> do
       shortHashLookup
  <||> standardHashLookup

shortHashLookup = debug "shortHashLookup" >> do
  char ':'
  hash <- saltyOptional <||> variable
  keys <- many1 $ hashKeyNumber <||> hashKeyOptional <||> hashKeyString
  return $ foldl (\acc key -> HashLookup acc key) (HashLookup hash (head keys)) (tail keys)

hashKeyNumber = debug "hashKeyString" >> do
  char '.'
  key <- many1 digit
  return $ SaltyNumber key

hashKeyOptional = debug "hashKeyOptional" >> do
  char '.'
  key <- many1 varNameChars
  char '?'
  return $ SaltyOptional $ SaltyString key

hashKeyString = debug "hashKeyString" >> do
  char '.'
  key <- many1 varNameChars
  return $ SaltyString key

standardHashLookup = debug "standardHashLookup" >> do
  hash <- variable
  char '['
  key <- validFuncArgTypes
  char ']'
  return $ HashLookup hash key

partialHashLookup = debug "partialHashLookup" >> do
  hash <- lastSalty <$> getState
  char '['
  key <- validFuncArgTypes
  char ']'
  return $ BackTrack (HashLookup hash key)

ifStatement = debug "ifStatement" >> do
       ifWithElse
  <||> ifWithoutElse
  <?> "an if statement"

ifWithElse = debug "ifWithElse" >> do
  string "if"
  space
  condition <- parseTill (wrapInSalt $ string " then ")
  thenFork <- saltyParserSingle_
  space
  string "else"
  space
  elseFork <- saltyParserSingle_
  return $ If condition thenFork (Just elseFork)

ifWithoutElse = debug "ifWithoutElse" >> do
  string "if"
  space
  condition <- parseTill (wrapInSalt $ string " then ")
  thenFork <- saltyParserSingle_
  return $ If condition thenFork Nothing

whileStatement = debug "whileStatement" >> do
  string "while"
  space
  condition <- saltyParserSingle_
  space
  body <- braces Nothing
  return $ While condition body

whereStatement = debug "whereStatement" >> do
  string "where"
  optional space
  modifyState (addScope ClassScope)
  body <- saltyParser
  optional space
  modifyState popScope
  debug $ "whereStatement done with: " ++ (show body)
  return $ Braces body

classDefinition = debug "classDefinition" >> do
  string "class"
  space
  name <- classVar
  space
  extendsName <- classDefExtends <||> nothing
  implementsName <- classDefImplements <||> nothing
  optional space
  body <- (braces (Just ClassScope) <||> whereStatement)
  return $ Class name extendsName implementsName body

classDefExtends = debug "classDefExtends" >> do
  string "extends"
  space
  extendsName <- classVar
  space
  return $ Just extendsName

classDefImplements = debug "classDefImplements" >> do
  string "implements"
  space
  implementsName <- classVar
  space
  return $ Just implementsName

nothing = return Nothing

objectCreation = debug "objectCreation" >> do
  string "new"
  space
  className <- classVar
  char '('
  constructorArgs <- findArgs
  char ')'
  return $ New className constructorArgs

saltyBool = debug "saltyBool" >> (saltyTrue <||> saltyFalse)

saltyTrue = debug "saltyTrue" >> do
  s <- string "true"
  return $ SaltyBool TRUE

saltyFalse = debug "saltyFalse" >> do
  s <- string "false"
  return $ SaltyBool FALSE

saltyNull = debug "saltyNull" >> do
  s <- string "null"
  return SaltyNull

saltyKeyword = debug "saltyKeyword" >> do
  phpKeyword <-      saltyKeywordUse
                <||> saltyKeywordThrow
                <||> saltyKeywordRequire
                <||> saltyKeywordRequireOnce
                <||> saltyKeywordConst
                <||> saltyKeywordPublic
                <||> saltyKeywordPrivate
                <||> saltyKeywordProtected
                <||> saltyKeywordStatic
                <||> saltyKeywordNamespace
                <||> saltyKeywordEcho
                <||> saltyKeywordBreak
  return $ Keyword phpKeyword

saltyKeywordUse = debug "saltyKeywordUse" >> do
  saltyKeywordUseAs <||> saltyKeywordUseOnly

saltyKeywordUseAs = debug "saltyKeywordUseAs" >> do
  string "use"
  space
  var <- variableName
  space
  string "as"
  space
  varAs <- variableName
  return $ KwUse var (Just varAs)

saltyKeywordUseOnly = debug "saltyKeywordUseOnly" >> do
  string "use"
  space
  var <- variableName
  return $ KwUse var Nothing

saltyKeywordThrow = debug "saltyKeywordThrow" >> do
  string "throw"
  space
  salty <- saltyParserSingle_
  return $ KwThrow salty

saltyKeywordRequire = debug "saltyKeywordRequire" >> do
  string "require"
  space
  salty <- saltyParserSingle_
  return $ KwRequire salty

saltyKeywordRequireOnce = debug "saltyKeywordRequireOnce" >> do
  string "require_once"
  space
  salty <- saltyParserSingle_
  return $ KwRequireOnce salty

saltyKeywordConst = debug "saltyKeywordConst" >> do
  string "const"
  space
  name <- many1 constChars
  return $ KwConst (PurePhp name)

saltyKeywordPublic = debug "saltyKeywordPublic" >> do
  string "public"
  space
  salty <- saltyParserSingle_
  return $ KwPublic salty

saltyKeywordPrivate = debug "saltyKeywordPrivate" >> do
  string "private"
  space
  salty <- saltyParserSingle_
  return $ KwPrivate salty

saltyKeywordProtected = debug "saltyKeywordProtected" >> do
  string "protected"
  space
  salty <- saltyParserSingle_
  return $ KwProtected salty

saltyKeywordStatic = debug "saltyKeywordStatic" >> do
  string "static"
  space
  salty <- saltyParserSingle_
  return $ KwStatic salty

saltyKeywordNamespace = debug "saltyKeywordNamespace" >> do
  string "namespace"
  space
  salty <- saltyParserSingle_
  return $ KwNamespace salty

saltyKeywordEcho = debug "saltyKeywordEcho" >> do
  string "echo"
  space
  salty <- saltyParserSingle_
  return $ KwEcho salty

saltyKeywordBreak = debug "saltyKeywordBreak" >> do
  string "break"
  return KwBreak

multiAssignVar = debug "multiAssignVar" >> do
  var <- variable
  string ", " <||> string " ="
  return var

multiAssign = debug "multiAssign" >> do
  firstVar <- multiAssignVar
  restVars <- many1 multiAssignVar
  space
  right <- saltyParserSingle_
  return $ MultiAssign (firstVar:restVars) right

plusplusAll = debug "plusplusAll" >> do
       plusplusStart
  <||> plusplusEnd
  <||> minusminusStart
  <||> minusminusEnd
  <?> "++ or -- statement"

plusplusStart = debug "plusplusStart" >> do
  string "++"
  var <- variable
  return $ Operation var PlusEquals (SaltyNumber "1")

plusplusEnd = debug "plusplusEnd" >> do
  var <- variable
  string "++"
  return $ Operation var PlusEquals (SaltyNumber "1")

minusminusStart = debug "minusminusStart" >> do
  string "--"
  var <- variable
  return $ Operation var MinusEquals (SaltyNumber "1")

minusminusEnd = debug "minusminusEnd" >> do
  var <- variable
  string "--"
  return $ Operation var MinusEquals (SaltyNumber "1")

magicConstant strToMatch toReturn = debug "saltyMagicConstant" >> do
  string strToMatch
  return toReturn

saltyMagicConstant = debug "saltyMagicConstant" >> do
  constant <-      magicConstant "__LINE__" MCLINE
              <||> magicConstant "__FILE__" MCFILE
              <||> magicConstant "__DIR__" MCDIR
              <||> magicConstant "__FUNCTION__" MCFUNCTION
              <||> magicConstant "__CLASS__" MCCLASS
              <||> magicConstant "__TRAIT__" MCTRAIT
              <||> magicConstant "__METHOD__" MCMETHOD
              <||> magicConstant "__NAMESPACE__" MCNAMESPACE
  return $ SaltyMagicConstant constant

validRangeArgTypes :: SaltyParser
validRangeArgTypes = debug "validRangeArgTypes" >> do
       saltyNumber
  <||> functionCall
  <||> attrAccess
  <||> hashLookup
  <||> partialHashLookup
  <||> partialFunctionCall
  <||> partialAttrAccess
  <||> negateSalty
  <||> saltyMagicConstant
  <||> variable
  <?> "a valid range argument type"

range = debug "range" >> do
  left <- validRangeArgTypes
  string ".."
  right <- validRangeArgTypes
  return $ Range left right

parseError = debug "parseError" >> do
  line <- many1 (noneOf "\n")
  char '\n'
  return $ ParseError line

phpVar = debug "phpVar" >> do
  char '$'
  name <- many1 varNameChars
  return $ PurePhp ('$':name)

saltyOptional = debug "saltyOptional" >> do
  var <- variable
  char '?'
  return $ SaltyOptional var
