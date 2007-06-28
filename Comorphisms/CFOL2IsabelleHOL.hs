{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski and Uni Bremen 2003-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

The embedding comorphism from CASL to Isabelle-HOL.
-}

module Comorphisms.CFOL2IsabelleHOL
    ( CFOL2IsabelleHOL(..)
    , transTheory
    , mapSen
    , IsaTheory
    , SignTranslator
    , FormulaTranslator
    , quantifyIsa
    , transSort
    , transOP_SYMB
    , var
    ) where

import Logic.Logic
import Logic.Comorphism

import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import CASL.Sublogic as SL
import CASL.Sign
import CASL.Morphism
import CASL.Quantification
import CASL.Fold

import Isabelle.IsaSign as IsaSign
import Isabelle.IsaConsts
import Isabelle.Logic_Isabelle
import Isabelle.Translate

import Common.AS_Annotation
import Common.Id
import Common.Result
import qualified Data.Map as Map
import qualified Data.Set as Set

import qualified Data.List as List
import Data.Maybe (mapMaybe)

isSingleton :: Set.Set a -> Bool
isSingleton s = Set.size s == 1

-- | The identity of the comorphism
data CFOL2IsabelleHOL = CFOL2IsabelleHOL deriving (Show)

-- Isabelle theories
type IsaTheory = (IsaSign.Sign, [Named IsaSign.Sentence])

-- extended signature translation
type SignTranslator f e = CASL.Sign.Sign f e -> e -> IsaTheory -> IsaTheory

-- extended signature translation for CASL
sigTrCASL :: SignTranslator () ()
sigTrCASL _ _ = id

-- extended formula translation
type FormulaTranslator f e = CASL.Sign.Sign f e -> f -> Term

-- extended formula translation for CASL
formTrCASL :: FormulaTranslator () ()
formTrCASL _ _ = error "CFOL2IsabelleHOL: No extended formulas allowed in CASL"

instance Language CFOL2IsabelleHOL -- default definition is okay

instance Comorphism CFOL2IsabelleHOL
               CASL CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign
               CASLMor
               Symbol RawSymbol ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign
               IsabelleMorphism () () ()  where
    sourceLogic _ = CASL
    sourceSublogic _ = SL.top
                      { sub_features = NoSub, -- no subsorting yet ...
                        has_part = False -- no partiality yet ...
                      }
    targetLogic _ = Isabelle
    mapSublogic cid sl = if sl `isSubElem` sourceSublogic cid
                       then Just () else Nothing
    map_theory _ = transTheory sigTrCASL formTrCASL
    map_morphism = mapDefaultMorphism
    map_sentence _ sign =
      return . mapSen formTrCASL sign
    map_symbol = errMapSymbol
    has_model_expansion _ = True
    is_weakly_amalgamable _ = True

---------------------------- Signature -----------------------------
baseSign :: BaseSig
baseSign = Main_thy

transTheory :: SignTranslator f e ->
               FormulaTranslator f e ->
               (CASL.Sign.Sign f e, [Named (FORMULA f)])
                   -> Result IsaTheory
transTheory trSig trForm (sign, sens) =
  fmap (trSig sign (extendedInfo sign)) $
  return (IsaSign.emptySign {
    baseSig = baseSign,
    tsig = emptyTypeSig {arities =
               Set.fold (\s -> let s1 = showIsaTypeT s baseSign in
                                 Map.insert s1 [(isaTerm, [])])
                               Map.empty (sortSet sign)},
    constTab = Map.foldWithKey insertPreds
                (Map.foldWithKey insertOps Map.empty
                $ opMap sign) $ predMap sign,
    domainTab = dtDefs},
         map (mapNamed myMapSen) real_sens)
     -- for now, no new sentences
  where
    myMapSen = mkSen . transTopFORMULA sign trForm (getAssumpsToks sign)
    (real_sens, sort_gen_axs) = List.partition
        (\ s -> case sentence s of
                Sort_gen_ax _ _ -> False
                _ -> True) sens
    dtDefs = makeDtDefs sign sort_gen_axs
    ga = globAnnos sign
    insertOps op ts m = if isSingleton ts then
      let t = Set.findMin ts in
           Map.insert (mkIsaConstT False ga (length $ opArgs t) op baseSign)
               (transOpType t) m
      else foldl (\m1 (t,i) ->
             Map.insert (mkIsaConstIT False ga
                         (length $ opArgs t) op i baseSign)
                    (transOpType t) m1) m
                (zip (Set.toList ts) [1..])
    insertPreds pre ts m = if isSingleton ts then
      let t = Set.findMin ts in
           Map.insert (mkIsaConstT True ga (length $ predArgs t) pre baseSign)
               (transPredType t) m
      else foldl (\m1 (t,i) ->
             Map.insert (mkIsaConstIT True ga
                         (length $ predArgs t) pre i baseSign)
                    (transPredType t) m1) m
                (zip (Set.toList ts) [1..])

makeDtDefs :: CASL.Sign.Sign f e -> [Named (FORMULA f)]
               -> [[(Typ,[(VName,[Typ])])]]
makeDtDefs sign = delDoubles . (mapMaybe $ makeDtDef sign)
  where
  delDoubles xs = delDouble xs []
  delDouble [] _  = []
  delDouble (x:xs) sortList = let (Type s _a _b) = fst (head x) in
      if (length sortList) ==
         (length (addSortList s sortList)) then
        delDouble xs sortList
      else
        (x:(delDouble xs (s:sortList)))
  addSortList x xs = (List.nub (x :xs))

makeDtDef :: CASL.Sign.Sign f e -> Named (FORMULA f) ->
             Maybe [(Typ,[(VName,[Typ])])]
makeDtDef sign nf = case sentence nf of
  Sort_gen_ax constrs True -> Just(map makeDt srts) where
    (srts,ops,_maps) = recover_Sort_gen_ax constrs
    makeDt s = (transSort s, map makeOp (filter (hasTheSort s) ops))
    makeOp opSym = (transOP_SYMB sign opSym, transArgs opSym)
    hasTheSort s (Qual_op_name _ ot _) = s == res_OP_TYPE ot
    hasTheSort _ _ = error "CFOL2IsabelleHOL.hasTheSort"
    transArgs (Qual_op_name _ ot _) = map transSort $ args_OP_TYPE ot
    transArgs _ = error "CFOL2IsabelleHOL.transArgs"
  _ -> Nothing

transSort :: SORT -> Typ
transSort s = Type (showIsaTypeT s baseSign) [] []

transOpType :: OpType -> Typ
transOpType ot = mkCurryFunType (map transSort $ opArgs ot)
                 $ transSort (opRes ot)

transPredType :: PredType -> Typ
transPredType pt = mkCurryFunType (map transSort $ predArgs pt) boolType

------------------------------ Formulas ------------------------------

getAssumpsToks :: CASL.Sign.Sign f e -> Set.Set String
getAssumpsToks sign = Map.foldWithKey ( \ i ops s ->
    Set.union s $ Set.unions
        $ zipWith ( \ o _ -> getConstIsaToks i o baseSign) [1..]
                     $ Set.toList ops)
    (Map.foldWithKey ( \ i prds s ->
    Set.union s $ Set.unions
        $ zipWith ( \ o _ -> getConstIsaToks i o baseSign) [1..]
                     $ Set.toList prds) Set.empty $ predMap sign) $ opMap sign

var :: String -> Term
var v = IsaSign.Free (mkVName v)

transVar :: Set.Set String -> VAR -> String
transVar toks v = let
    s = showIsaConstT (simpleIdToId v) baseSign
    renVar t = if Set.member t toks then renVar $ "X_" ++ t else t
    in renVar s

quantifyIsa :: String -> (String, Typ) -> Term -> Term
quantifyIsa q (v, _) phi =
  App (conDouble q) (Abs (var v) phi NotCont) NotCont

quantify :: Set.Set String -> QUANTIFIER -> (VAR, SORT) -> Term -> Term
quantify toks q (v,t) phi  =
  quantifyIsa (qname q) (transVar toks v, transSort t) phi
  where
  qname Universal = allS
  qname Existential = exS
  qname Unique_existential = ex1S

transOP_SYMB :: CASL.Sign.Sign f e -> OP_SYMB -> VName
transOP_SYMB sign (Qual_op_name op ot _) = let
  ga = globAnnos sign
  l = length $ args_OP_TYPE ot in
  case (do ots <- Map.lookup op (opMap sign)
           if isSingleton ots
             then return $ mkIsaConstT False ga l op baseSign
             else do
                   i <- List.elemIndex (toOpType ot) (Set.toList ots)
                   return $ mkIsaConstIT False ga l op (i+1) baseSign) of
    Just vn -> vn
    Nothing -> error ("CASL2Isabelle unknown op: " ++ show op)
transOP_SYMB _ (Op_name _) = error "CASL2Isabelle: unqualified operation"

transPRED_SYMB :: CASL.Sign.Sign f e -> PRED_SYMB -> VName
transPRED_SYMB sign (Qual_pred_name p pt@(Pred_type args _) _) = let
  ga = globAnnos sign
  l = length args in
  case (do pts <- Map.lookup p (predMap sign)
           if isSingleton pts
             then return $ mkIsaConstT True ga l p baseSign
             else do
                   i <- List.elemIndex (toPredType pt) (Set.toList pts)
                   return $ mkIsaConstIT True ga l p (i+1) baseSign) of
    Just vn -> vn
    Nothing -> error ("CASL2Isabelle unknown pred: " ++ show p)
transPRED_SYMB _ (Pred_name _) = error "CASL2Isabelle: unqualified predicate"

mapSen :: FormulaTranslator f e -> CASL.Sign.Sign f e -> FORMULA f -> Sentence
mapSen trForm sign phi =
    mkSen $ transTopFORMULA sign trForm (getAssumpsToks sign) phi

transTopFORMULA :: CASL.Sign.Sign f e -> FormulaTranslator f e
                -> Set.Set String -> FORMULA f -> Term
transTopFORMULA sign tr toks f = case f of
    Quantification Universal _ phi _ -> transTopFORMULA sign tr toks phi
    _ -> transFORMULA sign tr toks f

transRecord :: CASL.Sign.Sign f e -> FormulaTranslator f e -> Set.Set String
            -> Record f Term Term
transRecord sign tr toks = Record
    { foldQuantification = \ _ qu vdecl phi _ ->
          foldr (quantify toks qu) phi (flatVAR_DECLs vdecl)
    , foldConjunction = \ _ phis _ ->
          if null phis then true else foldr1 binConj phis
    , foldDisjunction = \ _ phis _ ->
          if null phis then false else foldr1 binDisj phis
    , foldImplication = \ _ phi1 phi2 _ _ -> binImpl phi1 phi2
    , foldEquivalence = \ _ phi1 phi2 _ -> binEqv phi1 phi2
    , foldNegation = \ _ phi _ -> termAppl notOp phi
    , foldTrue_atom = \ _ _ -> true
    , foldFalse_atom = \ _ _ -> false
    , foldPredication = \ _ psymb args _ ->
          foldl termAppl (con $ transPRED_SYMB sign psymb) args
    , foldDefinedness = \ _ _ _ -> true -- totality assumed
    , foldExistl_equation = \ _ t1 t2 _ -> binEq t1 t2 -- equal types assumed
    , foldStrong_equation = \ _ t1 t2 _ -> binEq t1 t2 -- equal types assumed
    , foldMembership = \ _ _ _ _ -> true -- no subsorting assumed
    , foldMixfix_formula = error "transRecord: Mixfix_formula"
    , foldSort_gen_ax = error "transRecord: Sort_gen_ax"
    , foldExtFORMULA = \ _ phi -> tr sign phi
    , foldSimpleId = error "transRecord: Simple_id"
    , foldQual_var = \ _ v _ _ -> var $ transVar toks v
    , foldApplication = \ _ opsymb args _ ->
          foldl termAppl (con $ transOP_SYMB sign opsymb) args
    , foldSorted_term = \ _ t _ _ -> t -- no subsorting assumed
    , foldCast = \ _ t _ _ -> t -- no subsorting assumed
    , foldConditional = \ _  t1 phi t2 _ -> -- equal types assumed
          foldl termAppl (conDouble "If") [phi, t1, t2]
    , foldMixfix_qual_pred = error "transRecord: Mixfix_qual_pred"
    , foldMixfix_term = error "transRecord: Mixfix_term"
    , foldMixfix_token = error "transRecord: Mixfix_token"
    , foldMixfix_sorted_term = error "transRecord: Mixfix_sorted_term"
    , foldMixfix_cast = error "transRecord: Mixfix_cast"
    , foldMixfix_parenthesized = error "transRecord: Mixfix_parenthesized"
    , foldMixfix_bracketed = error "transRecord: Mixfix_bracketed"
    , foldMixfix_braced = error "transRecord: Mixfix_braced"
    }

transFORMULA :: CASL.Sign.Sign f e -> FormulaTranslator f e -> Set.Set String
             -> FORMULA f -> Term
transFORMULA sign tr = foldFormula . transRecord sign tr
