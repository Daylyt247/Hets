{-# OPTIONS -cpp #-}
{- | 
   
   Module      :  $Header$
   Copyright   :  (c)  Till Mossakowski and Uni Bremen 2003
   Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

   Maintainer  :  hets@tzi.de
   Stability   :  provisional
   Portability :  non-portable
   
   Assembles all the logics into a list, as a prerequisite for the logic graph.
   The modules for the Grothendieck logic are logic graph indepdenent,
   and here is the logic graph that is used to instantiate these.
   Since the logic graph depends on a large number of modules for the
   individual logics, this separation of concerns (and possibility for
   separate compilation) is quite useful.

   References:

   J. A. Goguen, R. M. Burstall: Institutions: 
     Abstract Model Theory for Specification and Programming,
     Journal of the Association for Computing Machinery 39, p. 95-146.

   J. Meseguer: General logics. Logic Colloquium 87, p. 275-329, North Holland.

   Todo:
   Add many many logics.

-}

module Comorphisms.LogicList
where

import Common.Result
import Logic.Logic 
import Logic.Grothendieck
import CASL.Logic_CASL  -- also serves as default logic
import HasCASL.Logic_HasCASL
#ifdef PROGRAMATICA
import Haskell.Logic_Haskell
#endif
import CspCASL.Logic_CspCASL
import Isabelle.Logic_Isabelle
import Modal.Logic_Modal
import CoCASL.Logic_CoCASL
import qualified Common.Lib.Map as Map
import CASL.ATC_CASL

logicList :: [AnyLogic]
logicList = [Logic CASL, Logic HasCASL, 
#ifdef PROGRAMATICA
             Logic Haskell, 
#endif
	     Logic CoCASL, Logic Modal, Logic CspCASL, Logic Isabelle]

addLogicName :: AnyLogic -> (String,AnyLogic)
addLogicName l@(Logic lid) = (language_name lid, l)

defaultLogic :: AnyLogic
defaultLogic = Logic CASL

preLogicGraph :: LogicGraph
preLogicGraph = 
  LogicGraph {
    logics =      Map.fromList $ map addLogicName logicList,
    comorphisms = Map.empty,
    inclusions =  Map.empty
             }

-- currently only used in ATC/Grothendieck.hs
lookupLogic_in_LG :: String -> String -> AnyLogic
lookupLogic_in_LG errorPrefix logname =
    propagateErrors $ lookupLogic errorPrefix logname preLogicGraph

