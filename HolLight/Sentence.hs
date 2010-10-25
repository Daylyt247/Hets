{- |
Module      :  $Header$
Description :  Sentence for HolLight logic
Copyright   :  (c) Jonathan von Schroeder, DFKI GmbH 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  jonathan.von_schroeder@dfki.de
Stability   :  experimental
Portability :  portable

Definition of sentences for HolLight logic

  Ref.

  <http://www.cl.cam.ac.uk/~jrh13/hol-light/>

-}
module HolLight.Sentence where

data Sentence = Sentence {
  name :: String,
  term :: Term,
  proof :: Maybe HolProof
  } deriving (Eq, Ord, Show)

data HolProof = NoProof deriving (Eq, Ord, Show)

data HolType = TyVar String | TyApp String [HolType] deriving (Eq, Ord, Show)

data Term = Var String HolType
     | Const String HolType
     | Comb Term Term
     | Abs Term Term deriving (Eq, Ord, Show)

