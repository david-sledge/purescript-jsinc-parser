module Control.Monad.Nope.Trans
  ( NopeT
  , mapNopeT
  , nopeEither
  , nopeT
  , runNopeT
  )
  where

import Prelude

import Control.Monad.Maybe.Trans (MaybeT(MaybeT))
import Data.Maybe (Maybe(Nothing))
import Data.Either (Either, either)

-- | A monad transformer which adds failures to other monads, in the same way
-- | as `Nope`. As before, `a` is the type
-- | of successful results. The new type parameter `m` is the inner monad that
-- | computations run in.
type NopeT = MaybeT

nopeT ∷ ∀ m a. m (Maybe a) → NopeT m a
nopeT = MaybeT

-- | The inverse of `NopeT`. Run a computation in the `NopeT` monad.
runNopeT ∷ ∀ m a. NopeT m a → m (Maybe a)
runNopeT (MaybeT x) = x

-- | Transform the unwrapped computation using the given function.
mapNopeT ∷ ∀ m n a b. (m (Maybe a) → n (Maybe b)) → NopeT m a → NopeT n b
mapNopeT f (MaybeT m) = nopeT (f m)

-- | Construct a computation in the `NopeT` transformer from an `Either` value.
nopeEither ∷ ∀ e m a. Monad m ⇒ Either e a → NopeT m a
nopeEither = either (\ _ → nopeT $ pure Nothing) pure
