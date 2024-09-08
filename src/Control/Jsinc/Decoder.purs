module Control.Jsinc.Decoder
  ( DecodeExcption(..)
  , class DecodeJsonStream
  , decodeJsonStreamT
  , decodeJsonT
  , decodeLastChunkT
  , decodeT
  , endJsonDecodeT
  , endJsonStreamDecodeT
  , decodeLastChunkHelperT
  )
  where

import Prelude

import Control.Jsinc.Parser
  ( Event
  , ParseException(EOF)
  , ParseState
  , endJsonStreamParseT
  , initParseState
  , parseJsonStreamT
  , runParseT
  )
import Control.Monad.Error.Class (class MonadThrow)
import Control.Monad.Except (ExceptT, throwError)
import Control.Monad.Maybe.Trans (MaybeT)
import Control.Monad.State (class MonadState, StateT, get, modify, put)
import Data.Either (Either, either)
import Data.Maybe (Maybe(Just, Nothing), maybe)
import Data.Source (class Source)
import Data.Tuple (Tuple(Tuple))

data DecodeExcption e a
  = DecodeError e
  | ParseError ParseException
  | ShouldNeverHappen (Maybe a)

class DecodeJsonStream a e c m where
  decodeJsonT ∷
    MonadThrow (DecodeExcption e a) m ⇒
    c →
    Event →
    m (Tuple c (Maybe a))
  endJsonDecodeT ∷
    MonadThrow (DecodeExcption e a) m ⇒
    c →
    Event →
    m (Tuple c (Maybe (Maybe a)))

processJsonStreamT ∷ ∀ m a s c ev e a'.
  MonadState (Tuple s c) m ⇒
  MonadThrow (DecodeExcption e a') m ⇒
  (s → m (Tuple (Either ParseException ev) s)) →
  (c → ev → m (Tuple c (Maybe a))) →
  m a
processJsonStreamT f g =
  let recurse = do
        Tuple state acc ← get
        Tuple result state' ← f state
        put (Tuple state' acc)
        either (throwError <<< ParseError) (\ event → do
            (Tuple acc' mRes) ← g acc event
            modify (\ (Tuple state'' _) → Tuple state'' acc') *> maybe recurse pure mRes
          ) result
  in
  recurse

decodeJsonStreamT ∷ ∀ s a e c m.
  MonadState (Tuple (Tuple ParseState s) c) m ⇒
  MonadThrow (DecodeExcption e a) m ⇒
  Source s Char (MaybeT m) ⇒
  DecodeJsonStream a e c m ⇒
  m a
decodeJsonStreamT = processJsonStreamT parseJsonStreamT decodeJsonT

endJsonStreamDecodeT ∷ ∀ s a e c m.
  MonadState (Tuple (Tuple ParseState s) c) m ⇒
  MonadThrow (DecodeExcption e a) m ⇒
  DecodeJsonStream a e c m ⇒
  m (Maybe a)
endJsonStreamDecodeT = processJsonStreamT endJsonStreamParseT endJsonDecodeT

decodeLastChunkHelperT ∷ ∀ m s c a e.
  DecodeJsonStream a e c (ExceptT (DecodeExcption e a) (StateT (Tuple (Tuple ParseState s) c) m)) ⇒
  Monad m ⇒
  Source s Char (MaybeT (ExceptT (DecodeExcption e a) (StateT (Tuple (Tuple ParseState s) c) m))) ⇒
  a →
  Tuple (Tuple ParseState s) c →
  m (Tuple (Tuple (Maybe a) (DecodeExcption e a)) (Tuple (Tuple ParseState s) c))
decodeLastChunkHelperT a state = do
  -- When a value has already been supllied, the next call...
  Tuple result state' ← runParseT decodeJsonStreamT state
  pure $ Tuple (Tuple (Just a) $ either
      -- ... should return an exception...
      identity
      -- ... but not a value.
      (ShouldNeverHappen <<< Just)
      result) state'

-- | Finish decoding a JSON string.
decodeLastChunkT ∷ ∀ m s c a e.
  DecodeJsonStream a e c (ExceptT (DecodeExcption e a) (StateT (Tuple (Tuple ParseState s) c) m)) ⇒
  Monad m ⇒
  Source s Char (MaybeT (ExceptT (DecodeExcption e a) (StateT (Tuple (Tuple ParseState s) c) m))) ⇒
  Maybe a →
  Tuple (Tuple ParseState s) c →
  m (Tuple (Tuple (Maybe a) (Maybe (DecodeExcption e a))) (Tuple (Tuple ParseState s) c))
decodeLastChunkT mA state = do
  Tuple (Tuple mA' e') state'' ← maybe
    (do
      Tuple result state' ← runParseT decodeJsonStreamT state
      either
        (\ e → pure $ Tuple (Tuple Nothing e) state')
        (\ a → decodeLastChunkHelperT a state'
        ) result
    )
    (\ a → decodeLastChunkHelperT a state)
    mA
  case e' of
    ParseError EOF → maybe
      (do
        Tuple result state''' ← runParseT endJsonStreamDecodeT state''
        pure $ (either
            (\ e'' → Tuple (Tuple mA' $ Just e''))
            (\ mA'' → maybe
              (Tuple $ Tuple mA' <<< Just $ ShouldNeverHappen Nothing)
              (const $ Tuple (Tuple mA'' Nothing))
              mA''
            )
            result
          ) state''')
      (const <<< pure $ Tuple (Tuple mA' Nothing) state'')
      mA'
    _ → pure $ Tuple (Tuple mA' $ pure e') state''

-- | Decode a JSON string as a single chunk.
decodeT ∷ ∀ m s c a e.
  DecodeJsonStream a e c (ExceptT (DecodeExcption e a) (StateT (Tuple (Tuple ParseState s) c) m)) ⇒
  Monad m ⇒
  Source s Char (MaybeT (ExceptT (DecodeExcption e a) (StateT (Tuple (Tuple ParseState s) c) m))) ⇒
  s →
  c →
  m (Tuple (Tuple (Maybe a) (Maybe (DecodeExcption e a))) (Tuple (Tuple ParseState s) c))
decodeT src c = decodeLastChunkT Nothing $ Tuple (Tuple initParseState src) c
