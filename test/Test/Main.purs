module Test.Main
  ( main
  )
  where

import Prelude

import Control.Fix (fix)
import Control.Json.Parser (Event(..), ParseException(..), endParseT, initParseState, parseJsonNextValueT)
import Control.Monad.Nope (runNopeT)
import Data.Char (fromCharCode)
import Data.Either (Either(..), either)
import Data.Maybe (Maybe(Just, Nothing), fromMaybe, maybe)
import Data.Source (InPlaceString(InPlaceString), LineColumnPosition(LineColumnPosition), SourcePosition(SourcePosition), advance, peekSource, headSource)
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Class.Console (log)
import Test.Assert (assertEqual, assertTrue)
import Data.String.CodePoints (codePointFromChar, fromCodePointArray)

logShow str a = log $ str <> ": " <> show a

main ∷ Effect Unit
main = do
  log "fix"
  assertEqual
    { actual: (fix (\ fib n →
        if n < 3
        then 1
        else fib(n - 1) + fib(n - 2)) 7
      )
    , expected: 13
    }

  let source = InPlaceString "null" 0

  argh ← runNopeT $ peekSource source
  assertEqual
    { actual: argh
    , expected: Just 'n'
    }

  argh ← runNopeT $ headSource source
  assertEqual
    { actual: argh
    , expected: Just (Tuple 'n' $ InPlaceString "null" 1)
    }

  maybe (pure unit) (\ (Tuple c srcPos) -> do
      argh ← runNopeT $ headSource srcPos
      assertEqual
        { actual: argh
        , expected: Just (Tuple 'u' $ InPlaceString "null" 2)
        }
    ) argh

  let pos = LineColumnPosition 0 false 0 0

  argh ← advance 'n' pos
  assertEqual
    { actual: argh
    , expected: LineColumnPosition 1 false 0 1
    }

  let srcPos = SourcePosition source pos
      state = Tuple initParseState srcPos

  argh ← runNopeT $ peekSource srcPos
  assertEqual
    { actual: argh
    , expected: Just 'n'
    }

  argh ← runNopeT $ headSource srcPos
  assertEqual
    { actual: argh
    , expected: Just (Tuple 'n' $ SourcePosition (InPlaceString "null" 1) (LineColumnPosition 1 false 0 1))
    }

  maybe (pure unit) (\ (Tuple c srcPos) -> do
      argh ← runNopeT $ headSource srcPos
      assertEqual
        { actual: argh
        , expected: Just (Tuple 'u' $ SourcePosition (InPlaceString "null" 2) (LineColumnPosition 2 false 0 2))
        }
    ) argh

  argh ← runNopeT $ headSource srcPos
  assertEqual
    { actual: argh
    , expected: Just (Tuple 'n' $ SourcePosition (InPlaceString "null" 1) (LineColumnPosition 1 false 0 1))
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right ENull
    }

  let wrap str posi = SourcePosition (InPlaceString str 0) posi
      wrap' str = wrap str pos

  ------------------------------------------------------------------------------
  Tuple result (Tuple parseState (SourcePosition _ posi)) ← parseJsonNextValueT <<< Tuple initParseState $ wrap' " nul"
  assertEqual
    { actual: result
    , expected: Left EOF
    }

  Tuple result state@(Tuple parseState (SourcePosition _ posi)) ← parseJsonNextValueT <<< Tuple parseState $ wrap "l " posi
  assertEqual
    { actual: result
    , expected: Right ENull
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Left Done
    }

  ------------------------------------------------------------------------------
  Tuple result (Tuple parseState (SourcePosition _ posi)) ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\tfalse \n"
  assertEqual
    { actual: result
    , expected: Right (EBool false)
    }

  ------------------------------------------------------------------------------
  Tuple result (Tuple parseState (SourcePosition _ posi)) ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\ttrue"
  assertEqual
    { actual: result
    , expected: Right (EBool true)
    }

  ------------------------------------------------------------------------------
  Tuple result state@(Tuple parseState (SourcePosition _ posi)) ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\"\\ud800\\udc00\""
  assertEqual
    { actual: result
    , expected: Right EStringStart
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EString "\xd800\xdc00")
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EStringEnd
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Left Done
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\"rtr\\u0035\\nue\""
  assertEqual
    { actual: result
    , expected: Right EStringStart
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EString "rtr5\nue")
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EStringEnd
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Left Done
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\"rtr\\u00"
  assertEqual
    { actual: result
    , expected: Right EStringStart
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EString "rtr")
    }

  Tuple result (Tuple parseState (SourcePosition _ posi)) ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Left EOF
    }

  Tuple result state ← parseJsonNextValueT <<< Tuple parseState $ wrap "35ue\" " posi
  assertEqual
    { actual: result
    , expected: Right (EString "5ue")
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EStringEnd
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Left Done
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "0 "
  assertEqual
    { actual: result
    , expected: Right (ENumber 0.0)
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "0.0 "
  assertEqual
    { actual: result
    , expected: Right (ENumber (-0.0e+0))
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "-0.0 "
  assertEqual
    { actual: result
    , expected: Right (ENumber 0.0e-3)
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "-0.0e+0 "
  assertEqual
    { actual: result
    , expected: Right (ENumber (-0.0))
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "0.0e-03 "
  assertEqual
    { actual: result
    , expected: Right (ENumber 0.0)
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "0.125e+0022 "
  assertEqual
    { actual: result
    , expected: Right (ENumber 0.125e22)
    }

  ------------------------------------------------------------------------------
  Tuple result _ ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "-0.125e-0022 "
  assertEqual
    { actual: result
    , expected: Right (ENumber (-0.125e-22))
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "-0.125e-0022"
  assertEqual
    { actual: result
    , expected: Left EOF
    }

  Tuple result _ ← endParseT state
  assertEqual
    { actual: result
    , expected: Right (ENumber (-0.125e-22))
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "[]"
  assertEqual
    { actual: result
    , expected: Right EArrayStart
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EArrayEnd
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "[ null ]"
  assertEqual
    { actual: result
    , expected: Right EArrayStart
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right ENull
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EArrayEnd
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "[ true, null ]"

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EBool true)
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right ENull
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EArrayEnd
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\r{ \t}"
  assertEqual
    { actual: result
    , expected: Right EObjectStart
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EObjectEnd
    }

  ------------------------------------------------------------------------------
  Tuple result state ← parseJsonNextValueT <<< Tuple initParseState $ wrap' "\r{\"test\": null \t}"
  assertEqual
    { actual: result
    , expected: Right EObjectStart
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EStringStart)
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EString "test")
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right (EStringEnd)
    }

  Tuple result state ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right ENull
    }

  Tuple result _ ← parseJsonNextValueT state
  assertEqual
    { actual: result
    , expected: Right EObjectEnd
    }
