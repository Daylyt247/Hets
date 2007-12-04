{- |
Module      :  $Header$
Description :  Signatures of COL as extension of CASL signatures
Copyright   :  (c) Till Mossakowski, C. Maeder, Uni Bremen 2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Signatures of COL as extension of CASL signatures.
-}

module COL.COLSign where

import qualified Data.Set as Set
import qualified Data.Map as Map
import Common.Id

data COLSign = COLSign { constructors :: Set.Set Id
                       , observers :: Map.Map Id Int
                       } deriving (Show, Eq)

emptyCOLSign :: COLSign
emptyCOLSign = COLSign Set.empty Map.empty

addCOLSign :: COLSign -> COLSign -> COLSign
addCOLSign s1 s2 =
    s1 { constructors = Set.union (constructors s1) $ constructors s2
       , observers = Map.union (observers s1) $ observers s2 }

isSubCOLSign :: COLSign -> COLSign -> Bool
isSubCOLSign s1 s2 =
    Set.null (constructors s2 Set.\\ constructors s1)
    && Map.null (observers s2 Map.\\ observers s1)
