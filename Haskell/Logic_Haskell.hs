{-# OPTIONS -fno-warn-missing-methods #-}
{-| 
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Sonja Groening, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable(Logic)

   Here is the place where the class Logic is instantiated for Haskell.
   Also the instances for Syntax an Category.

   todo:
     - writing real functions

-}

module Haskell.Logic_Haskell (Haskell(..), empty_signature) where

import Logic.ParsecInterface    (toParseFun)
import Logic.Logic              {-(Language,
                                 Category,
                                 Syntax,
                                 Sentences,
                                 StaticAnalysis,
                                 Logic,
                                 parse_basic_spec,
                                 parse_symb_items,
                                 parse_symb_map_items,
                                 basic_analysis,
                                 empty_signature,
                                 signature_union,
                                 data_logic,
                                 sublogic_names,
                                 inclusion)-}
import Data.Dynamic            
import Haskell.ATC_Haskell      -- generated ATerm conversions

import System.IO.Unsafe (unsafePerformIO)
import Haskell.Hatchet.MultiModule (readModuleInfo)
import Haskell.Hatchet.MultiModuleBasics (ModuleInfo (..),
                                          joinModuleInfo,
                                          getTyconsMembers,
                                          getInfixDecls,
                                          emptyModuleInfo)
import Haskell.Hatchet.TIHetsModule          (tiModule)
import Haskell.Hatchet.AnnotatedHsSyn    (AHsDecl (..),
                                          AModule (..))
import Haskell.Hatchet.Env               (listToEnv,
                                          emptyEnv)
import Haskell.Hatchet.HaskellPrelude    (preludeDefs,
                                          tyconsMembersHaskellPrelude,
                                          preludeDataCons,
                                          preludeClasses,
                                          preludeTyconAndClassKinds,
                                          preludeInfixDecls,
                                          preludeSynonyms)
import Haskell.Hatchet.SynConvert        (toAHsModule)
import Haskell.Hatchet.Type              (assumpToPair)
import Haskell.Hatchet.Utils             (getAModuleName)
import Haskell.Hatchet.HsParsePostProcess (fixFunBindsInModule)
import Haskell.Hatchet.HsSyn             (HsModule (..),
                                          Module (..))
import Haskell.HatParser                 (HsDecls,
                                          hatParser)
import Haskell.HaskellUtils              (extractSentences)
import Common.Result                     (Result (..))
import Common.Lib.Pretty
import Common.PrettyPrint

import Haskell.ExtHaskellCvrt            (cvrtHsModule)

moduleInfoTc, hsDeclsTc, aHsDeclTc :: TyCon
moduleInfoTc   = mkTyCon "Haskell.Hatchet.MultiModuleBasics.ModuleInfo"
hsDeclsTc      = mkTyCon "Haskell.HatParser.HsDecls"
aHsDeclTc      = mkTyCon "Haskell.Hatchet.AnnotatedHsSyn.AHsDecl"

instance Typeable ModuleInfo where
    typeOf _ = mkAppTy moduleInfoTc []
instance Typeable HsDecls where
    typeOf _ = mkAppTy hsDeclsTc []
instance Typeable AHsDecl where
    typeOf _ = mkAppTy aHsDeclTc []


instance PrettyPrint ModuleInfo where
  printText0 _ modInfo = text "Module name" 
                                <+> text (show (moduleName modInfo)) 
                                <> comma
                          $+$ text "Variable Assumptions" 
                                <+> text (show (varAssumps modInfo))
                                <> comma
                          $+$ text "Data Constructor Assumptions" 
                                <+> text (show (dconsAssumps modInfo))
                                <> comma
                          $+$ text "Class Hierarchy" 
                                <+> text (show (classHierarchy modInfo))
                                <> comma
                          $+$ text "Kinds" 
                                <+> text (show (kinds modInfo))
                                <> comma
                          $+$ text "Synonyms" 
                                <+> text (show (synonyms modInfo))
                                <> comma
                          $+$ text "Infix Declarations" 
                                <+> text (show (infixDecls modInfo))
                                <> comma
                          $+$ text "Type Constructor Members" 
                                <+> text (show (tyconsMembers modInfo))
                                <> comma


instance PrintLaTeX ModuleInfo where
  printLatex0 = printText0
instance PrintLaTeX HsDecls where
  printLatex0 = printText0

-- a dummy datatype for the LogicGraph and for identifying the right
-- instances

data Haskell = Haskell deriving (Show)
instance Language Haskell  -- default definition is okay

type Sign = ModuleInfo 
type Morphism = ()

instance Category Haskell Sign Morphism where
  dom Haskell _ = empty_signature Haskell

-- abstract syntax, parsing (and printing)

type SYMB_ITEMS = ()
type SYMB_MAP_ITEMS = ()

instance Syntax Haskell HsDecls
		SYMB_ITEMS SYMB_MAP_ITEMS
      where 
         parse_basic_spec Haskell = Just(toParseFun hatParser ())
	 parse_symb_items Haskell = Nothing
	 parse_symb_map_items Haskell = Nothing

type Haskell_Sublogics = ()

type Sentence = AHsDecl
instance Ord AHsDecl where

type Symbol = ()
type RawSymbol = ()

instance Sentences Haskell Sentence () Sign Morphism Symbol

preludeSign :: ModuleInfo
preludeSign = ModuleInfo {
               moduleName = AModule "Prelude",
               varAssumps = (listToEnv $ map assumpToPair preludeDefs),
               tyconsMembers = tyconsMembersHaskellPrelude, 
               dconsAssumps = (listToEnv $ map assumpToPair preludeDataCons),
               classHierarchy = listToEnv preludeClasses,
               kinds = (listToEnv preludeTyconAndClassKinds),
               infixDecls = preludeInfixDecls,
               synonyms = preludeSynonyms
              }


{-   basic_analysis :: lid ->
                       Maybe((basic_spec,       -- abstract syntax tree
                              sign,             -- signature of imported
                                                   modules
                              GlobalAnnos) ->   -- global annotations
                       Result (basic_spec,      -- renamed module
                               sign,sign,       -- (total, delta)
                                  -- delta = deklarations in the modul
                                  -- total = imported + delta 
                               [Named sentence] -- programdefinitions))

  basic_analysis calculates from the abstract syntax tree the types of
  all functions and tests wether all used identifiers are declared

-}

instance StaticAnalysis Haskell HsDecls
               Sentence () 
               SYMB_ITEMS SYMB_MAP_ITEMS
               Sign 
               Morphism 
               Symbol RawSymbol 


  where
    empty_signature Haskell 
       = ModuleInfo { varAssumps = emptyEnv,
                      moduleName = AModule "EmptyModule",-- error "Unspecified module name",
                      dconsAssumps = emptyEnv,
                      classHierarchy = emptyEnv,
                      tyconsMembers = [], 
                      kinds = emptyEnv,
                      infixDecls = [],
                      synonyms = [] }
--          empty_signature Haskell = emptyModuleInfo
    signature_union Haskell sig1 sig2 = return (joinModuleInfo sig1 sig2)
    inclusion Haskell _ _ = return ()
--    sublogic_names Haskell _ = ["Haskell"]
    basic_analysis Haskell = Just(basicAnalysis)
      where basicAnalysis (basicSpec, sig, _) = 	            
             let basicMod = cvrtHsModule (HsModule (Module "Anonymous") 
                                                   Nothing [] basicSpec)

          -- re-group matches into their associated funbinds 
          -- (patch up the output from the parser)
                 moduleSyntaxFixedFunBinds = fixFunBindsInModule basicMod

          -- map the abstract syntax into the annotated abstract syntax
  		 annotatedSyntax = toAHsModule moduleSyntaxFixedFunBinds

                 (moduleEnv,
   		  dataConEnv,
   		  newClassHierarchy,
   		  newKindInfoTable,
   		  moduleIds,
   		  moduleRenamed,
   		  moduleSynonyms) = tiModule [] annotatedSyntax sig
  		 modInfo = ModuleInfo {
                            varAssumps = moduleEnv, 
    		            moduleName = getAModuleName annotatedSyntax,
    			    dconsAssumps = dataConEnv, 
    			    classHierarchy = newClassHierarchy,
    			    kinds = newKindInfoTable,
    			    tyconsMembers = getTyconsMembers moduleRenamed,
    			    infixDecls = getInfixDecls moduleRenamed,
    			    synonyms = moduleSynonyms }
             in
	        Result {diags = [],
		        maybeResult = Just(basicSpec, modInfo, 
                        (joinModuleInfo sig modInfo), 
                        (extractSentences annotatedSyntax)) }

instance Logic Haskell Haskell_Sublogics
               HsDecls Sentence SYMB_ITEMS SYMB_MAP_ITEMS
               Sign 
               Morphism
               Symbol RawSymbol ()
   where data_logic Haskell = Nothing
