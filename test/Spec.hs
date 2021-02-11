{-# LANGUAGE QuasiQuotes #-}
import Text.RawString.QQ


import Test.HUnit
import Parser
import Types
import ToPhp

-- so it prints multi-line strings on multiple lines for gods sake
-- assertEqual_ expected actual = assertBool (expected == actual) failureMsg
--   where failureMsg = "expected:\n" ++ expected ++"\nbut got actual:\n" ++ actual ++ "\n"

matches str1 str2 = TestCase $ assertEqual "" str2 (saltyToPhp 0 str1)

makeToPhpTest :: (Salty, String) -> Test
makeToPhpTest (salty,expectedStr) = (toPhp salty) `matches` expectedStr

saltyBlob = [r|
  isSafe str lists := lists.any(l -> l.isBlocked(str))

  isBlocked str := do
    return @list.any(term -> strpos(term, str) !== false)
    end

  isUnsafe str := !isSafe(str)
  |]

phpBlob = [r|
  function isSafe($str, $lists) {
    $result = false;
    foreach ($lists as $l) {
      if ($l->isBlocked($str)) {
        $result = true;
        break;
      }
    }
    return $result;
  }

  function isBlocked($str) {
    $result = false;
    foreach ($list as $term) {
      if (strpos(term, str) !== false) {
        $result = true;
        break;
      }
    }
    return $result;
  }

  function isUnsafe($str) {
    return !isSafe($str);
  }
  |]

longerTest = saltyBlob `matches` phpBlob

multiLineEach = [r|foo.each(x -> {
    x + 1
    y + 2
    hello("hi")
  })
|]

multiLineEachResult = [r|foreach ($foo as $x) {
    $x + 1;
    $y + 2;
    hello("hi");
}|]

multiLineEachTest = multiLineEach `matches` multiLineEachResult

multiLineMap = [r|foo.map(x -> {
    x + 1
    y + 2
    hello("hi")
  })
|]

multiLineMapResult = [r|$result = [];
foreach ($foo as $x) {
    $x + 1;
    $y + 2;
    $result []= hello("hi");
}|]

multiLineMapTest = multiLineMap `matches` multiLineMapResult

multiLineMapAssign = [r|myVar = foo.map(x -> {
    x + 1
    y + 2
    hello("hi")
  })
|]

multiLineMapAssignResult = [r|$myVar = [];
foreach ($foo as $x) {
    $x + 1;
    $y + 2;
    $myVar []= hello("hi");
}|]

multiLineMapAssignTest = multiLineMapAssign `matches` multiLineMapAssignResult

multiLineSelect = [r|foo.select(x -> {
    x + 1
    y + 2
    hello("hi")
  })
|]

multiLineSelectResult = [r|$result = [];
foreach ($foo as $x) {
    $x + 1;
    $y + 2;
    if(hello("hi")) {
        $result []= $x;
    }
}|]

multiLineSelectTest = multiLineSelect `matches` multiLineSelectResult

multiLineAny = [r|foo.any(x -> {
    x + 1
    y + 2
    hello("hi")
  })
|]

multiLineAnyResult = [r|$result = false;
foreach ($foo as $x) {
    $x + 1;
    $y + 2;
    if(hello("hi")) {
        $result = true;
        break;
    }
}|]

multiLineAnyTest = multiLineAny `matches` multiLineAnyResult

multiLineAll = [r|foo.all(x -> {
    x + 1
    y + 2
    hello("hi")
  })
|]

multiLineAllResult = [r|$result = true;
foreach ($foo as $x) {
    $x + 1;
    $y + 2;
    if(!hello("hi")) {
        $result = false;
        break;
    }
}|]

multiLineAllTest = multiLineAll `matches` multiLineAllResult

multiLineArrays = [r|
class Foo implements Bar where

foo := {
    [
        ["", "en", "US", "USD", false, false, false],
        ["", "en", "US", "USD", false, false, false],
    ]
}
|]

multiLineArraysTest = [r|class Foo implements Bar {
    public function foo() {
        return [
            ["", "en", "US", "USD", false, false, false],
            ["", "en", "US", "USD", false, false, false],
        ];
    }
}|]

guardTest = [r|foo := guard
  | x == 1 -> x.foo()
  | y == 2 -> x.map(y -> y + 1)
|]

guardResult = [r|function foo() {
    if ($x == 1) {
        return $x->foo();
    } elseif ($y == 2) {
        $result = [];
        foreach ($x as $y) {
            $result []= $y + 1;
        }
        return $result;
    }
}|]

guardTestWithArgs = [r|foo a bar := guard
  | x == 1 -> x.foo()
  | otherwise -> Foo.new().bar()
|]

guardResultWithArgs = [r|function foo($a, $bar) {
    if ($x == 1) {
        return $x->foo();
    } else {
        return (new Foo())->bar();
    }
}|]

guardTestWithWhere = [r|foo a bar := guard
  | awesome -> x.foo()
  | otherwise -> x.map(y -> y + 1)
  where awesome = 1 + 1
  and blossom = Foo.new()
|]

guardResultWithWhere = [r|function foo($a, $bar) {
    $awesome = 1 + 1;
    $blossom = (new Foo());
    if ($awesome) {
        return $x->foo();
    } else {
        $result = [];
        foreach ($x as $y) {
            $result []= $y + 1;
        }
        return $result;
    }
}|]

guardTestComplex = [r|foo :: bool
foo := guard
  | (bar in ["aa", "bb"]) && (baz in ["cc", "dd"]) -> true
  | bar == "fr" && baz == "fr" -> true
  | bar == "de" && baz == "de" -> true
  | otherwise -> false
|]

guardTestComplexResult = [r|/**
 * @return bool
 */
function foo() {
    if ((in_array($bar, ["aa", "bb"])) && (in_array($baz, ["cc", "dd"]))) {
        return true;
    } elseif ($bar == "fr" && $baz == "fr") {
        return true;
    } elseif ($bar == "de" && $baz == "de") {
        return true;
    } else {
        return false;
    }
}|]

transpileTests = [
    multiLineEachTest,
    multiLineMapTest,
    multiLineMapAssignTest,
    multiLineSelectTest,
    multiLineAnyTest,
    multiLineAllTest,
    multiLineArrays `matches` multiLineArraysTest,
    guardTest `matches` guardResult,
    guardTestWithArgs `matches` guardResultWithArgs,
    guardTestWithWhere `matches` guardResultWithWhere,
    guardTestComplex `matches` guardTestComplexResult,
    -- operations
    "foo = 1" `matches` "$foo = 1;",
    "bar = 'adit'" `matches` "$bar = \"adit\";",
    "@foo = 1" `matches` "$this->foo = 1;",
    "@@foo = 1" `matches` "static::$foo = 1;",

    "a = a - 1" `matches` "$a = $a - 1;",
    "a -= 1" `matches` "$a = $a - 1;",
    "a == 1" `matches` "$a == 1;",
    "5 * 5" `matches` "5 * 5;",
    "x % 2" `matches` "$x % 2;",
    "x % 2 == 0" `matches` "$x % 2 == 0;",
    "foo + bar" `matches` "$foo + $bar;",
    "'foo' + 'bar'" `matches` "\"foo\" + \"bar\";",
    "a + b + c" `matches` "$a + $b + $c;",

    "(a + 1) * 20" `matches` "($a + 1) * 20;",
    "(a + 1) * (b - 10)" `matches` "($a + 1) * ($b - 10);",
    "(a + (b * (c / 30)))" `matches` "($a + ($b * ($c / 30)));",
    "foo() + a.bar()" `matches` "foo() + $a->bar();",
    "foo []= bar" `matches` "$foo []= $bar;",
    "foo ++ bar" `matches` "$foo . $bar;",
    "foo <> bar" `matches` "array_merge($foo, $bar);",
    "foo <-> bar" `matches` "array_diff($foo, $bar);",
    "foo in bar" `matches` "in_array($foo, $bar);",
    "'foo' in bar" `matches` "in_array(\"foo\", $bar);",
    "foo keyin bar" `matches` "array_key_exists($foo, $bar);",
    "foo <=> bar" `matches` "$foo <=> $bar;",
    "foo = hello_there(hi(2) <> 1)" `matches` "$foo = hello_there(array_merge(hi(2), 1));",
    "foo = hello_there(hi(2) + 1)" `matches` "$foo = hello_there(hi(2) + 1);",
    "foo, bar, baz = []" `matches` "$foo = [];\n$bar = [];\n$baz = [];",
    "key = @@KEY ++ preg_replace('/[^a-z\\d_]/i', '_', str).join(\"_\") ++ last" `matches` "$key = static::KEY . implode('_', preg_replace(\"/[^a-z\\d_]/i\", \"_\", $str)) . $last;",

    -- function definitions
    "build a b := return 2" `matches` "function build($a, $b) {\n    return 2;\n}",
    "@@build a b := return 2" `matches` "static function build($a, $b) {\n    return 2;\n}",
    "incr a := return a + 1" `matches` "function incr($a) {\n    return $a + 1;\n}",
    "foo := a.foo()" `matches` "function foo() {\n    return $a->foo();\n}",
    "foo a b := a + 1 + b + 2" `matches` "function foo($a, $b) {\n    return $a + 1 + $b + 2;\n}",
    "foo a b := (a + 1) + (b - 2)" `matches` "function foo($a, $b) {\n    return ($a + 1) + ($b - 2);\n}",
    "foo a b := { a + b }" `matches` "function foo($a, $b) {\n    return $a + $b;\n}",
    -- no visibility (public/private) for functions in global scope:
    "_foo a := @a = a" `matches` "function foo($a) {\n    $this->a = $a;\n}",
    "@@_foo a := @a = a" `matches` "static function foo($a) {\n    $this->a = $a;\n}",
    -- but do add visibility in class scope:
    "class Foo {\n_foo a := @a = a\n}" `matches` "class Foo {\n    private function foo($a) {\n        $this->a = $a;\n    }\n}",
    "class Foo {\n@@_foo a := @a = a\n}" `matches` "class Foo {\n    private static function foo($a) {\n        $this->a = $a;\n    }\n}",
    "foo2 := 2 + 2" `matches` "function foo2() {\n    return 2 + 2;\n}",
    "__construct a := @a = a" `matches` "function __construct($a) {\n    $this->a = $a;\n}",
    "foo ...a := a" `matches` "function foo(...$a) {\n    return $a;\n}",

    -- pass by reference
    "incr &count := ++count" `matches` "function incr(&$count) {\n    $count = $count + 1;\n}",
    "foo a b := bar\n  where baz = b + 1\n  and bar = a + baz" `matches` "function foo($a, $b) {\n    $baz = $b + 1;\n    $bar = $a + $baz;\n    return $bar;\n}",

    -- fails, variables don't have the concept of pass by reference or not yet
    -- "foo = &bar" `matches` "$foo = &$bar",

    -- plus plus
    "++bar" `matches` "$bar = $bar + 1;",
    "bar++" `matches` "$bar = $bar + 1;",
    "--bar" `matches` "$bar = $bar - 1;",
    "bar--" `matches` "$bar = $bar - 1;",

    -- parens tests
    "(a + b)" `matches` "($a + $b);",
    "((a + b))" `matches` "(($a + $b));",
    "(((a + b)))" `matches` "((($a + $b)));",
    "(((foo())))" `matches` "(((foo())));",
    "(((a.foo())))" `matches` "((($a->foo())));",
    "((a + 1) * (b - 4))" `matches` "(($a + 1) * ($b - 4));",
    "(foo).bar" `matches` "($foo)->bar;",
    "(foo).bar()" `matches` "($foo)->bar();",
    "(new Foo()).bar()" `matches` "(new Foo())->bar();",

    "var = (new Foo(:hash.key)).someFunc()" `matches` "$var = (new Foo($hash[\"key\"]))->someFunc();",

    -- braces tests
    "fib x := {\nif x < 2 then {\nreturn x\n} else {\nreturn fib(x - 1) + fib(x - 2)\n}\n}" `matches` "function fib($x) {\n    if ($x < 2) {\n        return $x;\n    } else {\n        return fib($x - 1) + fib($x - 2);\n    }\n}",
    "fib x := {\na + b\n b + c\n }\n \n foo a b := a + b" `matches` "function fib($x) {\n    $a + $b;\n    return $b + $c;\n}\nfunction foo($a, $b) {\n    return $a + $b;\n}",
    "fib x := {\na + b\n b + c\n }\n \n foo a b := { a + b }" `matches` "function fib($x) {\n    $a + $b;\n    return $b + $c;\n}\nfunction foo($a, $b) {\n    return $a + $b;\n}",

    -- hash tests
    "argv[1]" `matches` "$argv[1];",
    "argv[1][2]" `matches` "$argv[1][2];",
    "fib(argv[1])" `matches` "fib($argv[1]);",
    "var_dump(fib(argv[1]))" `matches` "var_dump(fib($argv[1]));",

    -- hash dot notation tests
    ":foo.bar.baz" `matches` "$foo[\"bar\"][\"baz\"];",
    ":foo.bar.baz.1" `matches` "$foo[\"bar\"][\"baz\"][1];",
    ":argv.1.2" `matches` "$argv[1][2];",
    ":@foo.bar" `matches` "$this->foo[\"bar\"];",
    ":@@foo.bar" `matches` "static::$foo[\"bar\"];",
    ":bar.baz ?? 1" `matches` "$bar[\"baz\"] ?? 1;",

    -- if statement
    "if a = 1 then {\n b = 2\n c = 3\n }" `matches`"if ($a = 1) {\n    $b = 2;\n    $c = 3;\n}",
    "if a != 'foo' then return 2 else return 3" `matches` "if ($a != \"foo\") {\n    return 2;\n} else {\n    return 3;\n}",
    "foo := if x % 2 == 0 then 'even' else 'odd'" `matches` "function foo() {\n    if ($x % 2 == 0) {\n        return \"even\";\n    } else {\n        return \"odd\";\n    }\n}",

    -- arity for else
    "fib x := if x < 2 then x else fib(x - 1) + fib(x - 2)" `matches` "function fib($x) {\n    if ($x < 2) {\n        return $x;\n    } else {\n        return fib($x - 1) + fib($x - 2);\n    }\n}",

    -- while statement
    "while foo == 1 {\nfoo = 2\n}" `matches`"while ($foo == 1) {\n    $foo = 2;\n}",
    "while foo == 1 {\nfoo = 2\nbar = 3\n}" `matches`"while ($foo == 1) {\n    $foo = 2;\n    $bar = 3;\n}",

    -- function calls
    "Blocklist.foo()" `matches` "Blocklist::foo();",
    "a.foo()" `matches` "$a->foo();",
    "@a.foo()" `matches` "$this->a->foo();",
    "@foo()" `matches` "$this->foo();",
    "@@foo()" `matches` "static::foo();",

    "Blocklist.foo(1, 2)" `matches` "Blocklist::foo(1, 2);",
    "a.foo(1, 2)" `matches` "$a->foo(1, 2);",
    "@a.foo(1, 2)" `matches` "$this->a->foo(1, 2);",
    "@foo(1, 2)" `matches` "$this->foo(1, 2);",
    "@@foo(1, 2)" `matches` "static::foo(1, 2);",

    "Blocklist.foo(b)" `matches` "Blocklist::foo($b);",
    "a.foo(b)" `matches` "$a->foo($b);",
    "@a.foo(b)" `matches` "$this->a->foo($b);",
    "@foo(b)" `matches` "$this->foo($b);",
    "@@foo(b)" `matches` "static::foo($b);",

    "Blocklist.foo(b.bar())" `matches` "Blocklist::foo($b->bar());",
    "a.foo(b.bar())" `matches` "$a->foo($b->bar());",
    "@a.foo(@bar())" `matches` "$this->a->foo($this->bar());",
    "@foo(@@bar())" `matches` "$this->foo(static::bar());",
    "@@foo(@b.bar())" `matches` "static::foo($this->b->bar());",
    "a.foo().bar().baz().func().func2()" `matches` "$a->foo()->bar()->baz()->func()->func2();",
    "foo . bar . baz $ myVar" `matches` "foo(bar(baz($myVar)));",

    -- attr access
    "foo.bar" `matches` "$foo->bar;",
    "@foo.bar" `matches` "$this->foo->bar;",
    "@@foo.bar" `matches` "static::$foo->bar;",
    "Blocklist.foo" `matches` "Blocklist::$foo;",
    "Blocklist.FOO" `matches` "Blocklist::FOO;",
    "foo.bar = 1" `matches` "$foo->bar = 1;",
    "foo.bar = 'hello'" `matches` "$foo->bar = \"hello\";",
    "foo.bar = 2 + 2" `matches` "$foo->bar = 2 + 2;",

    -- negate
    "!foo" `matches` "!$foo;",

    -- class definition
    "class Blocklist {\n @foo := p(\"hi!\")\n }" `matches` "class Blocklist {\n    public function foo() {\n        return var_dump(\"hi!\");\n    }\n}",
    "class Blocklist extends Bar {\n @foo := p(\"hi!\")\n }" `matches` "class Blocklist extends Bar {\n    public function foo() {\n        return var_dump(\"hi!\");\n    }\n}",
    "class Blocklist implements Bar {\n @foo := p(\"hi!\")\n }" `matches` "class Blocklist implements Bar {\n    public function foo() {\n        return var_dump(\"hi!\");\n    }\n}",
    "class Blocklist extends Foo implements Bar {\n @foo := p(\"hi!\")\n }" `matches` "class Blocklist extends Foo implements Bar {\n    public function foo() {\n        return var_dump(\"hi!\");\n    }\n}",

    -- class creation with where
    "class Foo implements Bar where\n\nattr1 = 'hi'\n__construct name := @attr1 = name" `matches` "class Foo implements Bar {\n    public $attr1 = \"hi\";\n    public function __construct($name) {\n        $this->attr1 = $name;\n    }\n}",

    -- object creation
    "class Blocklist {\n@foo := p(\"hi!\")\n }\n b = new Blocklist()\n b.foo()" `matches` "class Blocklist {\n    public function foo() {\n        return var_dump(\"hi!\");\n    }\n}\n$b = new Blocklist();\n$b->foo();",

    -- function type signature
    "foo :: string\nfoo := 'hello'" `matches` "\n/**\n * @return string\n */\nfunction foo() {\n    return \"hello\";\n}",
    "foo :: string -> string\nfoo a := a" `matches` "\n/**\n * @param string\n * @return string\n */\nfunction foo(string $a) {\n    return $a;\n}",
    "foo :: string? -> string?\nfoo a := a" `matches` "\n/**\n * @param string|null\n * @return string|null\n */\nfunction foo(?string $a = null) {\n    return $a;\n}",
    "foo :: string? -> int -> string?\nfoo a b := a" `matches` "\n/**\n * @param string|null\n * @param int\n * @return string|null\n */\nfunction foo(?string $a = null, int $b) {\n    return $a;\n}",
    -- var type signature
    "var :: string" `matches` "\n/** @var string */",
    "var :: string?" `matches` "\n/** @var string|null */",
    -- null, true, false
    "a = true" `matches` "$a = true;",
    "b = false" `matches` "$b = false;",
    "c = null" `matches` "$c = null;",
    "_SAMPLE_RATE = 0.001" `matches` "_SAMPLE_RATE = 0.001;",
    "const _SAMPLE_RATE = 0.001" `matches` "const _SAMPLE_RATE = 0.001;",
    "foo = ONE + TWO" `matches` "$foo = ONE + TWO;",
    "class Foo {\n_SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    private const SAMPLE_RATE = 0.001;\n}",
    "class Foo {\nSAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    public const SAMPLE_RATE = 0.001;\n}",
    "class Foo {\n@@SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    public static const SAMPLE_RATE = 0.001;\n}",
    "class Foo {\n@@_SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    private static const SAMPLE_RATE = 0.001;\n}",
    "class Foo {\nconst _SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    const _SAMPLE_RATE = 0.001;\n}",
    "class Foo {\npublic const _SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    public const _SAMPLE_RATE = 0.001;\n}",
    "class Foo {\nprivate const _SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    private const _SAMPLE_RATE = 0.001;\n}",
    "class Foo {\npublic static const _SAMPLE_RATE = 0.001\n}" `matches` "class Foo {\n    public static const _SAMPLE_RATE = 0.001;\n}",

    -- return statements
    "return foo" `matches` "return $foo;",
    "return (1 + 2)" `matches` "return (1 + 2);",

    -- implicit returns
    "foo := 5" `matches` "function foo() {\n    return 5;\n}",
    "foo := bar = 5" `matches` "function foo() {\n    $bar = 5;\n}",
    "foo := bar []= 5" `matches` "function foo() {\n    $bar []= 5;\n}",
    "foo := \"hello\"" `matches` "function foo() {\n    return \"hello\";\n}",
    "foo x := if x then 'hi' else 'hello'" `matches` "function foo($x) {\n    if ($x) {\n        return \"hi\";\n    } else {\n        return \"hello\";\n    }\n}",
    "fib x := if x < 2 then x" `matches` "function fib($x) {\n    if ($x < 2) {\n        return $x;\n    }\n}",
    "foo := bar ||= 1" `matches` "function foo() {\n    $bar = $bar ?? 1;\n    return $bar;\n}",

    -- higher order functions
    "arr.any(x -> x == 1)" `matches`"$result = false;\nforeach ($arr as $x) {\n    if($x == 1) {\n        $result = true;\n        break;\n    }\n}",
    "arr.all(x -> x.isEven())" `matches`"$result = true;\nforeach ($arr as $x) {\n    if(!$x->isEven()) {\n        $result = false;\n        break;\n    }\n}",
    "arr.select(x -> x.isEven())" `matches`"$result = [];\nforeach ($arr as $x) {\n    if($x->isEven()) {\n        $result []= $x;\n    }\n}",
    "arr.each(x -> print(x))" `matches`"foreach ($arr as $x) {\n    print($x);\n}",
    "@adit.map(x -> x + 1)" `matches` "$result = [];\nforeach ($this->adit as $x) {\n    $result []= $x + 1;\n}",
    -- same but w parens
    "(@adit).map(x -> x + 1)" `matches` "$result = [];\nforeach ($this->adit as $x) {\n    $result []= $x + 1;\n}",
    "users = shops.map(s -> s.user)" `matches`"$users = [];\nforeach ($shops as $s) {\n    $users []= $s->user;\n}",
    "users = shops.map(s x -> s.user)" `matches` "$users = [];\nforeach ($shops as $s => $x) {\n    $users []= $s->user;\n}",
    "shops.each(s x -> s.user)" `matches` "foreach ($shops as $s => $x) {\n    $s->user;\n}",
    "@shops().each(s -> s.user)" `matches` "foreach ($this->shops() as $s) {\n    $s->user;\n}",
    "[foo, bar, baz].map(shop -> shop.listings)" `matches` "$result = [];\nforeach ([$foo, $bar, $baz] as $shop) {\n    $result []= $shop->listings;\n}",
    "foo[:5].map(shop -> shop.listings)" `matches` "$result = [];\nforeach (array_slice($foo, 0, 5) as $shop) {\n    $result []= $shop->listings;\n}",
    "@shops().find(1).each(s -> s.user)" `matches` "foreach ($this->shops()->find(1) as $s) {\n    $s->user;\n}",
    "Foo.shops(arg1).each(s -> s.user)" `matches` "foreach (Foo::shops($arg1) as $s) {\n    $s->user;\n}",
    "@@shops().map(s -> s.user)" `matches` "$result = [];\nforeach (static::shops() as $s) {\n    $result []= $s->user;\n}",
    "Foo.shops().any(s -> s.user)" `matches`"$result = false;\nforeach (Foo::shops() as $s) {\n    if($s->user) {\n        $result = true;\n        break;\n    }\n}",
    "@shops().all(s -> s.user)" `matches` "$result = true;\nforeach ($this->shops() as $s) {\n    if(!$s->user) {\n        $result = false;\n        break;\n    }\n}",
    "@shops().select(s -> s.user)" `matches` "$result = [];\nforeach ($this->shops() as $s) {\n    if($s->user) {\n        $result []= $s;\n    }\n}",

    -- chain a function onto the end of a HoF
    "count_alive = shops.select(s -> s.isAlive()).count()" `matches` "$count_alive = [];\nforeach ($shops as $s) {\n    if($s->isAlive()) {\n        $count_alive []= $s;\n    }\n}\n$count_alive = count($count_alive);",
    "count_alive = shops.select(s -> s.isAlive()).foo()" `matches` "$count_alive = [];\nforeach ($shops as $s) {\n    if($s->isAlive()) {\n        $count_alive []= $s;\n    }\n}\n$count_alive = $count_alive->foo();",
    -- TODO attr access and array slices don't work on this
    -- "count_alive = shops.select(\\s -> s.isAlive()).foo" `matches` "",
    -- "count_alive = shops.select(\\s -> s.isAlive())[:2]" `matches` "",
    -- TODO can't chain more than one function yet
    -- "count_alive = shops.select(\\s -> s.isAlive()).uniq().count()" `matches` "",

    -- assigning accVar manually
    "myAcc = foo.each(x -> print(x))" `matches` "foreach ($foo as $x) {\n    print($x);\n}",
    "@myAcc = foo.map(x -> x + 1)" `matches` "$this->myAcc = [];\nforeach ($foo as $x) {\n    $this->myAcc []= $x + 1;\n}",
    "@@myAcc = foo.any(x -> x.isEven())" `matches` "static::$myAcc = false;\nforeach ($foo as $x) {\n    if($x->isEven()) {\n        static::$myAcc = true;\n        break;\n    }\n}",
    "myAcc = foo.all(x -> x.isEven())" `matches` "$myAcc = true;\nforeach ($foo as $x) {\n    if(!$x->isEven()) {\n        $myAcc = false;\n        break;\n    }\n}",

    -- assigning accVar manually plus implicit return
    "bar := myAcc = foo.each(x -> print(x))" `matches` "function bar() {\n    foreach ($foo as $x) {\n        print($x);\n    }\n}",
    "bar := @myAcc = foo.map(x -> x + 1)" `matches` "function bar() {\n    $this->myAcc = [];\n    foreach ($foo as $x) {\n        $this->myAcc []= $x + 1;\n    }\n    return $this->myAcc;\n}",
    "bar := @@myAcc = foo.any(x -> x.isEven())" `matches` "function bar() {\n    static::$myAcc = false;\n    foreach ($foo as $x) {\n        if($x->isEven()) {\n            static::$myAcc = true;\n            break;\n        }\n    }\n    return static::$myAcc;\n}",
    "bar := myAcc = foo.all(x -> x.isEven())" `matches` "function bar() {\n    $myAcc = true;\n    foreach ($foo as $x) {\n        if(!$x->isEven()) {\n            $myAcc = false;\n            break;\n        }\n    }\n    return $myAcc;\n}",

    -- implicit returns for higher order functions
    "bar := foo.each(x -> print(x))" `matches` "function bar() {\n    foreach ($foo as $x) {\n        print($x);\n    }\n}",
    "bar := foo.map(x -> x + 1)" `matches`"function bar() {\n    $result = [];\n    foreach ($foo as $x) {\n        $result []= $x + 1;\n    }\n    return $result;\n}",
    "bar := foo.any(x -> x.isEven())" `matches`"function bar() {\n    $result = false;\n    foreach ($foo as $x) {\n        if($x->isEven()) {\n            $result = true;\n            break;\n        }\n    }\n    return $result;\n}",
    "bar := foo.all(x -> x.isEven())" `matches`"function bar() {\n    $result = true;\n    foreach ($foo as $x) {\n        if(!$x->isEven()) {\n            $result = false;\n            break;\n        }\n    }\n    return $result;\n}",
    "bar := foo.select(x -> x.isEven())" `matches` "function bar() {\n    $result = [];\n    foreach ($foo as $x) {\n        if($x->isEven()) {\n            $result []= $x;\n        }\n    }\n    return $result;\n}",

    -- keywords
    "use Foo" `matches` "use Foo;",
    "use Foo\\Bar" `matches` "use Foo\\Bar;",
    "throw new Exception()" `matches` "throw new Exception();",
    "throw new Exception('foo')" `matches` "throw new Exception(\"foo\");",
    "throw e" `matches` "throw $e;",
    "require 'foo.php'" `matches` "require \"foo.php\";",
    "require_once 'foo.php'" `matches` "require_once \"foo.php\";",
    "namespace Foo" `matches` "namespace Foo;",
    "namespace Foo\\Bar" `matches` "namespace Foo\\Bar;",
    "echo 'hi'" `matches` "echo \"hi\";",
    "greet := echo 'hi'" `matches` "function greet() {\n    echo \"hi\";\n}",
    "break" `matches` "break;",

    -- arrays
    "foo = [1, 2, 3,]" `matches` "$foo = [1, 2, 3];",
    "foo = [1, 2, 3]" `matches` "$foo = [1, 2, 3];",
    "a = {\n foo: 1,\n bar: 2,\n cat: 'hello',\n }" `matches` "$a = [\n    \"foo\" => 1,\n    \"bar\" => 2,\n    \"cat\" => \"hello\"\n];",
    "a = {\n foo: 1,\n bar: 2,\n cat: 'hello'\n }" `matches` "$a = [\n    \"foo\" => 1,\n    \"bar\" => 2,\n    \"cat\" => \"hello\"\n];",

    -- array slices
    "foo[1:]" `matches` "array_slice($foo, 1);",
    "foo[:2]" `matches` "array_slice($foo, 0, 2);",
    "foo[:]" `matches` "array_slice($foo, 0);",
    "foo[1:5]" `matches` "array_slice($foo, 1, 4);",
    "foo[start:]" `matches` "array_slice($foo, $start);",
    "foo[2:count(foo)]" `matches` "array_slice($foo, 2, count($foo) - 2);",

    -- array splices
    "foo[1:] = arr" `matches` "array_splice($foo, 1, null, $arr);",
    "foo[:2] = arr" `matches` "array_splice($foo, 0, 2, $arr);",
    "foo[:] = arr" `matches` "array_splice($foo, 0, null, $arr);",
    "foo[1:5] = arr" `matches` "array_splice($foo, 1, 4, $arr);",
    "foo[start:] = arr" `matches` "array_splice($foo, $start, null, $arr);",
    "foo[2:count(foo)] = arr" `matches` "array_splice($foo, 2, count($foo) - 2, $arr);",

    -- string slices
    "foo<1>" `matches` "substr($foo, 1, 1);",
    "foo<1:>" `matches` "substr($foo, 1);",
    "foo<:2>" `matches` "substr($foo, 0, 2);",
    "foo<:>" `matches` "substr($foo, 0);",
    "foo<1:5>" `matches` "substr($foo, 1, 4);",
    "foo<start:>" `matches` "substr($foo, $start);",
    "foo<2:count(foo)>" `matches` "substr($foo, 2, count($foo) - 2);",
    -- instanceof
    "foo instanceof Class" `matches` "$foo instanceof Class;",
    "foo isa Class" `matches` "$foo instanceof Class;",

    -- string interpolation
    "oranges = \"I have ${number} oranges to eat.\"" `matches` "$oranges = \"I have ${number} oranges to eat.\";",
    "foo = \"hello $there\"" `matches` "$foo = \"hello $there\";",

    -- magic constants
    "foo = __FILE__" `matches` "$foo = __FILE__;",
    "foo = __LINE__" `matches` "$foo = __LINE__;",
    "foo = __DIR__" `matches` "$foo = __DIR__;",
    "foo = __FUNCTION__" `matches` "$foo = __FUNCTION__;",
    "foo = __CLASS__" `matches` "$foo = __CLASS__;",
    "foo = __TRAIT__" `matches` "$foo = __TRAIT__;",
    "foo = __METHOD__" `matches` "$foo = __METHOD__;",
    "foo = __NAMESPACE__" `matches` "$foo = __NAMESPACE__;",

    -- ranges
    "1..10" `matches` "[1,2,3,4,5,6,7,8,9,10];",
    "1..foo.bar" `matches` "a range: (1..$foo->bar);",
    "start..end" `matches` "a range: ($start..$end);",

    -- TODO failing spec
    -- "take(5, (1..10))" `matches` "take(5, [1,2,3,4,5,6,7,8,9,10]);",
    "take(5, 1..10)" `matches` "take(5, [1,2,3,4,5,6,7,8,9,10]);",

    -- classic for loop using each + range
    "(1..10).each(x -> x + 1)" `matches` "for ($x = 1; $x <= 10; $x++) {\n    $x + 1;\n}",
    "(start..end).each(x -> x + 1)" `matches` "for ($x = $start; $x <= $end; $x++) {\n    $x + 1;\n}",
    "foo in 1..10" `matches` "$foo >= 1 && $foo <= 10;",
    "foo in (1..10)" `matches` "$foo >= 1 && $foo <= 10;",
    "foo in (start..end.baz)" `matches` "$foo >= $start && $foo <= $end->baz;",
    "if foo in (start..end.baz) then {\nhi()\n}" `matches` "if ($foo >= $start && $foo <= $end->baz) {\n    hi();\n}",

    -- scope
    "class Foo {\nbar = 1\n}" `matches` "class Foo {\n    public $bar = 1;\n}",
    "class Foo {\n_bar = 1\n}" `matches` "class Foo {\n    private $bar = 1;\n}",
    "class Foo {\n@@_bar = 1\n}" `matches` "class Foo {\n    private static $bar = 1;\n}",
    "class Foo {\n@@bar = 1\n}" `matches` "class Foo {\n    public static $bar = 1;\n}",

    -- strip semicolons
    "foo = 1;\nbar = 2" `matches` "$foo = 1;\n$bar = 2;",

    -- don't fail on dollar signs
    "$foo = 1;\n$bar = 2;" `matches` "$foo = 1;\n$bar = 2;",

    -- optional
    "foo?" `matches` "!is_null($foo);",
    "foo?.bar" `matches` "if (!is_null($foo)) {\n    $foo->bar;\n}",
    "@foo?.bar" `matches` "if (!is_null($this->foo)) {\n    $this->foo->bar;\n}",
    "@@foo?.bar" `matches` "if (!is_null(static::$foo)) {\n    static::$foo->bar;\n}",
    "foo?.bar()" `matches` "if (!is_null($foo)) {\n    $foo->bar();\n}",
    "@foo?.bar()" `matches` "if (!is_null($this->foo)) {\n    $this->foo->bar();\n}",
    "@@foo?.bar()" `matches` "if (!is_null(static::$foo)) {\n    static::$foo->bar();\n}",
    "var = foo?.bar" `matches` "if (!is_null($foo)) {\n    $var = $foo->bar;\n}",
    "var = foo?.bar()" `matches` "if (!is_null($foo)) {\n    $var = $foo->bar();\n}",
    "var += foo?.bar" `matches` "if (!is_null($foo)) {\n    $var = $var + $foo->bar;\n}",
    "var *= foo?.bar()" `matches` "if (!is_null($foo)) {\n    $var = $var * $foo->bar();\n}",
    "foo?.map(x -> x + 1)" `matches` "if (!is_null($foo)) {\n    $result = [];\n    foreach ($foo as $x) {\n        $result []= $x + 1;\n    }\n}",
    "var = foo?.map(x -> x + 1)" `matches` "if (!is_null($foo)) {\n    $var = [];\n    foreach ($foo as $x) {\n        $var []= $x + 1;\n    }\n}",
    "foo := bar?" `matches` "function foo() {\n    return !is_null($bar);\n}",
    "foo := bar?.map(x -> x + 1)" `matches` "function foo() {\n    if (!is_null($bar)) {\n        $result = [];\n        foreach ($bar as $x) {\n            $result []= $x + 1;\n        }\n    }\n    return $result;\n}",
    "var = :foo?.bar" `matches` "if (!is_null($foo)) {\n    $var = $foo[\"bar\"];\n}",

    -- TODO
    -- "foo?.bar?.baz" `matches` "",
    -- "foo?.bar()?.baz" `matches` "",
    -- "foo?.bar()?.baz?" `matches` "",

    -- ternary
    "func := if var == 0 then 0 else 1" `matches` "function func() {\n    if ($var == 0) {\n        return 0;\n    } else {\n        return 1;\n    }\n}",
    "var2 = if var == 0 then 0 else 1" `matches` "$var2 = $var == 0 ? 0 : 1;",
    "func := if var == 0 then (if var2 == 1 then 1 else 2) else 1" `matches` "function func() {\n    if ($var == 0) {\n        return (if ($var2 == 1) {\n            1;\n        } else {\n            2;\n        });\n    } else {\n        return 1;\n    }\n}",

    -- backticks for php
    "'foo' ++ `'bar' . 'baz'`" `matches` "\"foo\" . 'bar' . 'baz';",

    -- hash table
    "{a: 1, [b]: 2, [@c]: 3}" `matches` "[\n    \"a\" => 1,\n    $b => 2,\n    $this->c => 3\n];",
    "{ stemmed: stemmed, unstemmed: unstemmed }" `matches` "[\n    \"stemmed\" => $stemmed,\n    \"unstemmed\" => $unstemmed\n];",

    -- string
    "\"foo\"" `matches` "\"foo\";",
    "'foo'" `matches` "\"foo\";",
    "\"'foo'\"" `matches` "\"'foo'\";",
    "\"'foo' and 'bar'\"" `matches` "\"'foo' and 'bar'\";",
    "\"<div class='foo bar'>\"" `matches` "\"<div class='foo bar'>\";",

    -- built in functions
    "foo.split(',')" `matches` "explode(',', $foo);",
    "foo.join(',')" `matches` "implode(',', $foo);",
    "foo.uniq()" `matches` "array_unique($foo);",
    "foo.pop()" `matches` "array_pop($foo);",
    "foo.keys()" `matches` "array_keys($foo);",
    "foo.values()" `matches` "array_values($foo);",
    "foo.reverse()" `matches` "array_reverse($foo);",
    "foo.count()" `matches` "count($foo);",
    "foo.size()" `matches` "count($foo);",
    "foo.shuffle()" `matches` "shuffle($foo);",
    "foo.split(',').uniq()" `matches` "array_unique(explode(',', $foo));",
    "foo.sub(\"foo\", 'bar')" `matches` "str_replace(\"foo\", \"bar\", $foo);",
    "foo.sub(\"foo\", bar)" `matches` "str_replace(\"foo\", $bar, $foo);",
    "Array.new(3, true)" `matches` "(new Array(3,true));",

    -- multi-assign
    "foo, bar = baz" `matches` "$foo = $baz[0];\n$bar = $baz[1];",
    "foo, bar = null" `matches` "$foo = null;\n$bar = null;",
    "foo, bar = 0" `matches` "$foo = 0;\n$bar = 0;",
    "foo, bar = explode('.', array)" `matches` "$result = explode(\".\", $array);\n$foo = $result[0];\n$bar = $result[1];",
    "foo, bar = obj.func()" `matches` "$result = $obj->func();\n$foo = $result[0];\n$bar = $result[1];",
    "foo, bar = Foo.new(bar).run()" `matches` "$result = (new Foo($bar))->run();\n$foo = $result[0];\n$bar = $result[1];",

    -- new keyword
    "new self()" `matches` "new self();",
    "new self(1, foo)" `matches` "new self(1,$foo);"


    -- empty hash
    -- disabling this feature since the syntax becomes ambiguous
    -- "{}" `matches` "[];",
    -- "foo = {}" `matches` "$foo = [];",
    -- "a, b, foo = {}" `matches` "$a = [];\n$b = [];\n$foo = [];",
    -- "foo := {}" `matches` "function foo() {\n}",
    -- "foo := return {}" `matches` "function foo() {\n    return [];\n}",
    -- "foo := { {} }" `matches` "function foo() {\n    return [];\n}"

    -- unsure what to do with this
    -- "if 1 == 1 then {}" `matches` ""


    -- comments at the end of the line
    -- "a + b # hi\nhello = 1" `matches` "$a + $b;\n$hello = 1;",
    -- "a + b // hi\nhello = 1" `matches` "$a + $b; // hi\n$hello = 1;"

    -- "p 'hello' if hash ? str" `matches` [r|
    --   if (isset($hash['str'])) {
    --     var_dump 'hello';
    --     }|],
    -- "hash > str" `matches` "$hash[$str]",
    -- "hash > str > str2 > str3" `matches` "$hash[$str][$str2][$str3]",
    -- "arr.map(\b acc -> b+1)" `matches` [r|
    --   $acc = [];
    --   foreach ($arr as $b) {
    --     $acc []= $b+1;
    --   }
    -- |],
    -- "arr.filter \b acc -> b > :is_stem" `matches` [r|
    --   $acc = [];
    --   foreach ($arr as $b) {
    --     if ($b['is_stem']) {
    --       $acc []= $b;
    --     }
    --   }
    -- |],
    -- [r|arr.each \b ->
    --   b[word] <$> \ids ->
    --       ids.each \id ->
    --         hits[id] ||= 0
    --         hits[id] += 1

    -- |] `matches` [r|
    --   foreach ($b as $arr) {
    --     if (isset($b[$word])) {
    --       $ids = $b[$word];
    --       foreach ($ids as $id) {
    --         $hits[$id] = $hits[$id] ?? 0;
    --         $hits[$id] = $hits[$id] + 1;
    --       }
    --     }
    --   }
    -- |],
    -- "arr.any \b acc -> b > :is_stem" `matches` [r|
    --   $acc = false;
    --   foreach ($arr as $b) {
    --     if ($b['is_stem']) {
    --       $acc = true;
    --       break;
    --     }
    --   }
    -- |],
    -- "arr.all \b acc -> b > :is_stem" `matches` [r|
    --   $acc = true;
    --   foreach ($arr as $b) {
    --     if (!$b['is_stem']) {
    --       $acc = false;
    --       break;
    --     }
    --   }
    -- |],
    -- "return @@memcache.allCacheKeys(@@buildKey(blocklists, loc || default_loc()))" `matches` [r|
    --   return static::memcache()->allCacheKeys(static::buildKey($blocklists, $loc ?? default_loc()));
    -- |],
    -- "return @@memcache.allCacheKeys $ @@buildKey(blocklists, loc || default_loc())" `matches` [r|
    --   return static::memcache()->allCacheKeys(static::buildKey($blocklists, $loc ?? default_loc()));
    -- |],
    -- "b ||= []" `matches` "$b = $b ?? []",
    -- "Blocklist lists" `matches` "new Blocklist($lists)",
    -- "foo.uniq" `matches` "array_unique($foo)",
    -- "array_merge $ a b c" `matches` "array_merge($a, $b, $c)"
  ]

-- assignmentTests = map makeToPhpTest $ [
--     -- equals
--     (Assignment (SimpleVar "foo") Equals (SaltyNumber "1"), "$foo = 1"),
--     (Assignment (InstanceVar "foo") Equals (SaltyNumber "1"), "$this->foo = 1"),
--     (Assignment (ClassVar "foo") Equals (SaltyNumber "1"), "self::foo = 1"),

--     -- plusequals
--     (Assignment (SimpleVar "foo") PlusEquals (SaltyNumber "1"), "$foo = $foo + 1"),
--     (Assignment (InstanceVar "foo") PlusEquals (SaltyNumber "1"), "$this->foo = $this->foo + 1"),
--     (Assignment (ClassVar "foo") PlusEquals (SaltyNumber "1"), "self::foo = self::foo + 1"),

--     -- minusequals
--     (Assignment (SimpleVar "foo") MinusEquals (SaltyNumber "1"), "$foo = $foo - 1"),
--     (Assignment (InstanceVar "foo") MinusEquals (SaltyNumber "1"), "$this->foo = $this->foo - 1"),
--     (Assignment (ClassVar "foo") MinusEquals (SaltyNumber "1"), "self::foo = self::foo - 1"),

--     -- orequals
--     (Assignment (SimpleVar "foo") OrEquals (SaltyNumber "1"), "$foo = $foo ?? 1"),
--     (Assignment (InstanceVar "foo") OrEquals (SaltyNumber "1"), "$this->foo = $this->foo ?? 1"),
--     (Assignment (ClassVar "foo") OrEquals (SaltyNumber "1"), "self::foo = self::foo ?? 1")
--   ]

-- functionTests = map makeToPhpTest $ [
--     -- different types of functions (instance vs class)
--     (Function (SimpleVar "foo") [Argument (Just "array") "arg1" Nothing] (OneLine $ SaltyNumber "1"), "function foo(array $arg1) {\n1;\n}"),
--     (Function (InstanceVar "foo") [Argument (Just "array") "arg1" Nothing] (OneLine $ SaltyNumber "1"), "function foo(array $arg1) {\n1;\n}"),
--     (Function (ClassVar "foo") [Argument (Just "array") "arg1" Nothing] (OneLine $ SaltyNumber "1"), "static function foo(array $arg1) {\n1;\n}"),

--     -- different numbers of args
--     (Function (InstanceVar "foo") [Argument (Just "array") "arg1" Nothing, Argument (Just "string") "arg2" Nothing] (OneLine $ SaltyNumber "1"), "function foo(array $arg1, string $arg2) {\n1;\n}"),
--     (Function (InstanceVar "foo") [Argument (Just "array") "arg1" Nothing, Argument (Just "string") "arg2" Nothing, Argument (Just "EP_Locale") "loc" Nothing] (OneLine $ SaltyNumber "1"), "function foo(array $arg1, string $arg2, EP_Locale $loc) {\n1;\n}"),

--     -- default args
--     (Function (InstanceVar "foo") [Argument (Just "array") "arg1" Nothing, Argument (Just "string") "arg2" $ Just "null"] (OneLine $ SaltyNumber "1"), "function foo(array $arg1, ?string $arg2 = null) {\n1;\n}"),

--     -- different types of function bodies
--     (Function (SimpleVar "foo") [Argument (Just "array") "arg1" Nothing] (OneLine $ Assignment (SimpleVar "foo") Equals (SaltyNumber "1")), "function foo(array $arg1) {\n$foo = 1;\n}"),
--     (Function (SimpleVar "foo") [Argument (Just "array") "arg1" Nothing] (Block [Assignment (SimpleVar "foo") Equals (SaltyNumber "1"), Assignment (SimpleVar "foo") PlusEquals (SaltyNumber "1")]), "function foo(array $arg1) {\n$foo = 1;\n$foo = $foo + 1;\n}"),
--     (Function (SimpleVar "foo") [Argument (Just "array") "arg1" Nothing] (AmpersandFunction (SimpleVar "foo")), "ampersand function body not allowed as method body SimpleVar \"foo\""),
--     -- (Function (SimpleVar "foo") [Argument (Just "array") "arg1" Nothing] (LambdaFunction ["a", "b"] $ AmpersandFunction (SimpleVar "foo")), "lambda function body not allowed as method body SimpleVar \"foo\""),

--     (SaltyNumber "123", "123"),
--     (SaltyNumber "123.0", "123.0"),
--     (SaltyString "hello there", "hello there"),
--     -- function calls
--     -- type of function (instance/class)
--     (FunctionCall Nothing (SimpleVar "foo") [], "foo()"),
--     (FunctionCall Nothing (InstanceVar "foo") [], "$this->foo()"),
--     (FunctionCall Nothing (ClassVar "foo") [], "static::foo()"),

--     -- calls on an object, function is simplevar
--     (FunctionCall (Just $ SimpleVar "obj") (SimpleVar "foo") [], "$obj->foo()"),
--     (FunctionCall (Just $ InstanceVar "obj") (SimpleVar "foo") [], "$this->obj->foo()"),
--     (FunctionCall (Just $ ClassVar "obj") (SimpleVar "foo") [], "static::obj->foo()"),

--     -- calls on an object, function is instancevar. No difference from simplevar.
--     (FunctionCall (Just $ SimpleVar "obj") (InstanceVar "foo") [], "$obj->foo()"),
--     (FunctionCall (Just $ InstanceVar "obj") (InstanceVar "foo") [], "$this->obj->foo()"),
--     (FunctionCall (Just $ ClassVar "obj") (InstanceVar "foo") [], "static::obj->foo()"),

--     -- calls on an object, function is classvar. No difference from simplevar.
--     (FunctionCall (Just $ SimpleVar "obj") (ClassVar "foo") [], "$obj->foo()"),
--     (FunctionCall (Just $ InstanceVar "obj") (ClassVar "foo") [], "$this->obj->foo()"),
--     (FunctionCall (Just $ ClassVar "obj") (ClassVar "foo") [], "static::obj->foo()"),

--     -- pass args to function calls (single arg)
--     (FunctionCall Nothing (SimpleVar "foo") ["1"], "foo(1)"),
--     (FunctionCall Nothing (InstanceVar "foo") ["1"], "$this->foo(1)"),
--     (FunctionCall Nothing (ClassVar "foo") ["1"], "static::foo(1)"),

--     -- pass args to function calls (multiple args)
--     (FunctionCall Nothing (SimpleVar "foo") ["1", "2"], "foo(1, 2)"),
--     (FunctionCall Nothing (InstanceVar "foo") ["1", "2"], "$this->foo(1, 2)"),
--     (FunctionCall Nothing (ClassVar "foo") ["1", "2"], "static::foo(1, 2)"),

--     -- higher order calls
--     (HigherOrderFunctionCall (SimpleVar "foo") Each (AmpersandFunction (SimpleVar "funcName")), "foreach ($foo as $i) {\nfuncName($i);\n}"),
--     (HigherOrderFunctionCall (SimpleVar "foo") Each (AmpersandFunction (InstanceVar "funcName")), "foreach ($foo as $i) {\n$i->funcName();\n}"),
--     (HigherOrderFunctionCall (SimpleVar "foo") Each (LambdaFunction ["a"] (SaltyNumber "1")), "foreach ($foo as $a) {\n1;\n}"),
--     (HigherOrderFunctionCall (SimpleVar "foo") Each (LambdaFunction ["a"] (Assignment (SimpleVar "a") Equals (SaltyNumber "1"))), "foreach ($foo as $a) {\n$a = 1;\n}"),

--     (HigherOrderFunctionCall (SimpleVar "foo") Map (AmpersandFunction (SimpleVar "funcName")), "$acc = [];\nforeach ($foo as $i) {\n$acc []= funcName($i);\n}"),
--     (HigherOrderFunctionCall (SimpleVar "foo") Map (AmpersandFunction (InstanceVar "funcName")), "$acc = [];\nforeach ($foo as $i) {\n$acc []= $i->funcName();\n}"),
--     (HigherOrderFunctionCall (SimpleVar "foo") Map (LambdaFunction ["a", "newList"] (SaltyNumber "1")), "$newList = [];\nforeach ($foo as $a) {\n$newList []= 1;\n}"),
--     (HigherOrderFunctionCall (SimpleVar "foo") Map (LambdaFunction ["a", "newList"] (Assignment (SimpleVar "a") Equals (SaltyNumber "1"))), "$newList = [];\nforeach ($foo as $a) {\n$newList []= ($a = 1);\n}"),

--     -- hash lookup
--     (HashLookup (Left (SimpleVar "hash")) (SimpleVar "key"), "$hash[$key]"),
--     (HashLookup (Left (InstanceVar "hash")) (InstanceVar "key"), "$this->hash[$this->key]"),
--     (HashLookup (Left (ClassVar "hash")) (ClassVar "key"), "static::$hash[static::$key]"),
--     (HashLookup (Right (HashLookup (Left (InstanceVar "hash")) (InstanceVar "key"))) (ClassVar "key2"), "$this->hash[$this->key][static::$key2]")
--   ]

allTests = TestList $
              transpileTests
            -- assignmentTests
            -- ++ functionTests


main :: IO ()
main = runTestTT allTests >> return ()
