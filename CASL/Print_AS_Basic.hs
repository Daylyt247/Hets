{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Christian Maeder and Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable

pretty printing data types of 'BASIC_SPEC'
-}

-- to do: remove the "Dangerous hack"

module CASL.Print_AS_Basic where

import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.Print_AS_Annotation
import Common.Keywords
import Common.Lib.Pretty
import Common.PrettyPrint
import qualified Common.Doc as Doc
import Common.DocUtils

import CASL.AS_Basic_CASL
import CASL.ToDoc

instance (PrettyPrint b, PrettyPrint s, PrettyPrint f) =>
    PrettyPrint (BASIC_SPEC b s f) where
    printText0 ga = Doc.toText ga . 
         printBASIC_SPEC (fromText ga) (fromText ga) (fromText ga)

instance (PrettyPrint b, PrettyPrint s, PrettyPrint f) =>
    PrettyPrint (BASIC_ITEMS b s f) where
    printText0 ga = Doc.toText ga . 
         printBASIC_ITEMS (fromText ga) (fromText ga) (fromText ga)


printFormulaAux :: PrettyPrint f => GlobalAnnos -> [Annoted (FORMULA f)] -> Doc
printFormulaAux ga f =
  vcat $ map (printAnnotedFormula_Text0 ga True) f

printAnnotedFormula_Text0 :: PrettyPrint f =>
                             GlobalAnnos -> Bool -> Annoted (FORMULA f) -> Doc
printAnnotedFormula_Text0 ga withDot = Doc.toText ga . Doc.printAnnoted 
           ((if withDot then (Doc.bullet Doc.<+>) else id) . fromText ga)

instance (PrettyPrint s, PrettyPrint f) => PrettyPrint (SIG_ITEMS s f) where
    printText0 ga = Doc.toText ga . printSIG_ITEMS (fromText ga) (fromText ga) 


instance PrettyPrint f => PrettyPrint (SORT_ITEM f) where
    printText0 ga = Doc.toText ga . printSortItem (fromText ga)

instance PrettyPrint f => PrettyPrint (OP_ITEM f) where
    printText0 ga = Doc.toText ga . printOpItem (fromText ga)

optQuMark :: FunKind -> Doc
optQuMark Partial = text quMark
optQuMark Total = empty

instance PrettyPrint OP_TYPE where
    printText0 = toOldText

instance PrettyPrint OP_HEAD where
    printText0 = toOldText

instance PrettyPrint ARG_DECL where
    printText0 ga = Doc.toText ga . printArgDecl

instance PrettyPrint f => PrettyPrint (OP_ATTR f) where
    printText0 ga = Doc.toText ga . printAttr (fromText ga)

instance PrettyPrint f => PrettyPrint (PRED_ITEM f) where
    printText0 ga = Doc.toText ga . printPredItem (fromText ga)

instance PrettyPrint PRED_TYPE where
    printText0 = toOldText

instance PrettyPrint PRED_HEAD where
    printText0 ga = Doc.toText ga . printPredHead

instance PrettyPrint DATATYPE_DECL where
    printText0 = toOldText

instance PrettyPrint ALTERNATIVE where
    printText0 = toOldText

instance PrettyPrint COMPONENTS where
    printText0 = toOldText

instance PrettyPrint VAR_DECL where
    printText0 = toOldText

printFORMULA :: PrettyPrint f => GlobalAnnos -> FORMULA f -> Doc
printFORMULA ga = Doc.toText ga . printFormula (fromText ga)

printTheoryFormula :: PrettyPrint f => GlobalAnnos -> Named (FORMULA f) -> Doc
printTheoryFormula ga f = printAnnotedFormula_Text0 ga
    (case sentence f of
    Quantification Universal _ _ _ -> False
    Sort_gen_ax _ _ -> False
    _ -> True) $ Doc.fromLabelledSen f 

instance PrettyPrint f => PrettyPrint (FORMULA f) where
    printText0 = printFORMULA

instance PrettyPrint PRED_SYMB where
    printText0 = toOldText

instance PrettyPrint f => PrettyPrint (TERM f) where
    printText0 ga = Doc.toText ga . printTerm (fromText ga)

instance PrettyPrint OP_SYMB where
    printText0 = toOldText

instance PrettyPrint SYMB_ITEMS where
    printText0 = toOldText

instance PrettyPrint SYMB_MAP_ITEMS where
    printText0 = toOldText

instance PrettyPrint SYMB_KIND where
    printText0 = toOldText

instance PrettyPrint SYMB where
    printText0 = toOldText

instance PrettyPrint TYPE where
    printText0 = toOldText

instance PrettyPrint SYMB_OR_MAP where
    printText0 = toOldText


