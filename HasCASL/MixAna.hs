{- |
Module      :  $Header$
Description :  mixfix analysis for terms
Copyright   :  (c) Christian Maeder and Uni Bremen 2003-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable

Mixfix analysis of terms and patterns, type annotations are also analysed
-}

module HasCASL.MixAna where

import Common.GlobalAnnotations
import Common.Result
import Common.Id
import Common.DocUtils
import Common.Earley
import Common.Lexer
import Common.Prec
import Common.ConvertMixfixToken
import Common.Lib.State
import Common.AnnoState
import qualified Data.Map as Map
import qualified Data.Set as Set

import HasCASL.As
import HasCASL.AsUtils
import HasCASL.PrintAs
import HasCASL.Unify
import HasCASL.VarDecl
import HasCASL.Le
import HasCASL.HToken
import HasCASL.ParseTerm
import HasCASL.TypeAna

import qualified Text.ParserCombinators.Parsec as P

import Data.Maybe
import Data.List (partition)
import Control.Exception (assert)

addType :: Term -> Term -> Term
addType (MixTypeTerm q ty ps) t = TypedTerm t q ty ps
addType _ _ = error "addType"

isCompoundList :: Set.Set [Id] -> [Term] -> Bool
isCompoundList compIds l =
    maybe False (flip Set.member compIds) $ sequence $ map termToId l

isTypeList :: Env -> [Term] -> Bool
isTypeList e l = case sequence $ map termToType l of
                 Nothing -> False
                 Just ts ->
                     let Result ds ml =
                             mapM ( \ t -> anaTypeM (Nothing, t) e) ts
                     in isJust ml && not (hasErrors ds)

termToType :: Term -> Maybe Type
termToType t =
    case P.runParser (parseType << P.eof) (emptyAnnos ()) "" $ showDoc t "" of
      Right x -> Just x
      _ -> Nothing

termToId :: Term -> Maybe Id
termToId t = case P.parse (uninstOpId << P.eof) "" $ showDoc t "" of
               Right x -> Just x
               _ -> Nothing

iterateCharts :: GlobalAnnos ->  Set.Set [Id] -> [Term] -> Chart Term
              -> State Env (Chart Term)
iterateCharts ga compIds terms chart =
    do e <- get
       let self = iterateCharts ga compIds
           oneStep = nextChart addType toMixTerm ga chart
           vs = localVars e
           tm = typeMap e
       case terms of
         [] -> return chart
         t:tt -> do
             let recurse trm = self tt $
                          oneStep (trm, exprTok {tokPos = getRange trm})
             case t of
                    MixfixTerm ts -> self (ts ++ tt) chart
                    MixTypeTerm q typ ps -> do
                       mTyp <- anaStarType typ
                       case mTyp of
                           Nothing -> recurse t
                           Just nTyp -> self tt $ oneStep
                                        (MixTypeTerm q (monoType nTyp) ps,
                                         typeTok {tokPos = ps})
                    BracketTerm b ts ps ->
                      let bres = self (expandPos TermToken
                                       (getBrackets b) ts ps ++ tt) chart
                      in case (b, ts) of
                        (Squares, _ : _) ->
                            if isCompoundList compIds ts then bres
                            else if isTypeList e ts then self tt $ oneStep
                                 (t, typeInstTok {tokPos = ps})
                                 else bres
                        _ -> bres
                    QualVar (VarDecl v typ ok ps) -> do
                       mTyp <- anaStarType typ
                       case mTyp of
                           Nothing -> recurse t
                           Just nType -> recurse $ QualVar $
                                         VarDecl v (monoType nType) ok ps
                    QualOp b (InstOpId v ts qs) sc ps -> do
                       mSc <- anaTypeScheme sc
                       newTs <- anaInstTypes ts
                       case mSc of
                           Nothing -> recurse t
                           Just nSc -> do
                               case findOpId e v nSc of
                                    Nothing -> addDiags [mkDiag Error
                                                   "operation not found" v]
                                    _ -> return ()
                               recurse $ QualOp b (InstOpId v newTs qs) nSc ps
                    QuantifiedTerm quant decls hd ps -> do
                       newDs <- mapM (anaddGenVarDecl False) decls
                       mt <- resolve ga hd
                       putLocalVars vs
                       putTypeMap tm
                       let newT = case mt of Just trm -> trm
                                             _ -> hd
                       recurse $ QuantifiedTerm quant (catMaybes newDs) newT ps
                    LambdaTerm decls part hd ps -> do
                       mDecls <- mapM (resolvePattern ga) decls
                       let anaDecls = catMaybes mDecls
                           bs = concatMap extractVars anaDecls
                       checkUniqueVars bs
                       mapM_ (addLocalVar False) bs
                       mt <- resolve ga hd
                       putLocalVars vs
                       recurse $ LambdaTerm anaDecls part (maybe hd id mt) ps
                    CaseTerm hd eqs ps -> do
                       mt <- resolve ga hd
                       newEs <- resolveCaseEqs ga eqs
                       recurse $ CaseTerm (maybe hd id mt) newEs ps
                    LetTerm b eqs hd ps -> do
                       newEs <- resolveLetEqs ga eqs
                       mt <- resolve ga hd
                       putLocalVars vs
                       recurse $ LetTerm b newEs (maybe hd id mt) ps
                    TermToken tok -> do
                        let (ds1, trm) = convertMixfixToken
                                         (literal_annos ga)
                                         ResolvedMixTerm TermToken tok
                        addDiags ds1
                        self tt $ oneStep $
                                       case trm of
                                                TermToken _ -> (trm, tok)
                                                _ -> (trm, exprTok
                                                      {tokPos = tokPos tok})
                    AsPattern vd p ps -> do
                        mp <- resolvePattern ga p
                        let newP = case mp of Just pat -> pat
                                              Nothing -> p
                        recurse $ AsPattern vd newP ps
                    TypedTerm trm k ty ps -> do
                        -- assume that type is analysed
                        mt <- resolve ga trm
                        recurse $ TypedTerm (maybe trm id mt) k ty ps
                    _ -> error ("iterCharts: " ++ show t)

-- * equation stuff
resolveCaseEq :: GlobalAnnos -> ProgEq -> State Env (Maybe ProgEq)
resolveCaseEq ga (ProgEq p t ps) =
    do mp <- resolvePattern ga p
       case mp of
           Nothing -> return Nothing
           Just newP -> do
                let bs = extractVars newP
                checkUniqueVars bs
                vs <- gets localVars
                mapM_ (addLocalVar False) bs
                mtt <- resolve ga t
                putLocalVars vs
                return $ case mtt of
                    Nothing -> Nothing
                    Just newT -> Just $ ProgEq newP newT ps

resolveCaseEqs :: GlobalAnnos -> [ProgEq] -> State Env [ProgEq]
resolveCaseEqs _ [] = return []
resolveCaseEqs ga (eq : rt) =
    do mEq <- resolveCaseEq ga eq
       eqs <- resolveCaseEqs ga rt
       return $ case mEq of
               Nothing -> eqs
               Just newEq -> newEq : eqs

resolveLetEqs :: GlobalAnnos -> [ProgEq] -> State Env [ProgEq]
resolveLetEqs _ [] = return []
resolveLetEqs ga (ProgEq pat trm ps : rt) =
    do mPat <- resolvePattern ga pat
       case mPat of
           Nothing -> do resolve ga trm
                         resolveLetEqs ga rt
           Just newPat -> do
               let bs = extractVars newPat
               checkUniqueVars bs
               mapM_ (addLocalVar False) bs
               mTrm <- resolve ga trm
               case mTrm of
                   Nothing -> resolveLetEqs ga rt
                   Just newTrm -> do
                       eqs <- resolveLetEqs ga rt
                       return (ProgEq newPat newTrm ps : eqs)

mkPatAppl :: Term -> Term -> Range -> Term
mkPatAppl op arg qs =
    case op of
            QualVar (VarDecl i (MixfixType []) _ _) ->
                ResolvedMixTerm i [arg] qs
            _ -> ApplTerm op arg qs

toMixTerm :: Id -> [Term] -> Range -> Term
toMixTerm i ar qs =
    if i == applId then assert (length ar == 2) $
           let [op, arg] = ar in mkPatAppl op arg qs
    else if i == tupleId || i == unitId then
         mkTupleTerm ar qs
    else case unPolyId i of
           Just j@(Id ts [] ps) ->
              if isMixfix j && isSingle ar then
                   ResolvedMixTerm j [] qs
              else assert (length ar == 1 + placeCount j) $
              let (toks, _) = splitMixToken ts
                  (far, _tar : sar) = splitAt (placeCount $ Id toks [] ps) ar
              in ResolvedMixTerm j (far ++ sar) qs
           _ -> ResolvedMixTerm i ar qs

getKnowns :: Id -> Set.Set Token
getKnowns (Id ts cs _) = Set.union (Set.fromList ts) $
                         Set.unions (map getKnowns cs)

resolvePattern :: GlobalAnnos -> Pattern -> State Env (Maybe Pattern)
resolvePattern = resolver True

resolve :: GlobalAnnos -> Term -> State Env (Maybe Term)
resolve = resolver False

resolver :: Bool -> GlobalAnnos -> Term -> State Env (Maybe Term)
resolver isPat ga trm =
    do ass <- gets assumps
       vs <- gets localVars
       ps <- gets preIds
       compIds <- gets getCompoundLists
       let (addRule, ruleS, sIds) = makeRules ga ps (getPolyIds ass)
                 $ Set.union (Map.keysSet ass) $ Map.keysSet vs
       chart <- iterateCharts ga compIds [trm] $ initChart addRule ruleS
       let Result ds mr = getResolved
              (showDoc . parenTerm) (getRange trm)
                          toMixTerm chart
       addDiags ds
       if isPat then case mr of
           Nothing -> return mr
           Just pat -> fmap Just $ anaPattern sIds pat
           else return mr

getPolyIds :: Assumps -> Set.Set Id
getPolyIds = Set.unions . map ( \ (i, OpInfos l) ->
            foldr ( \ oi s -> case opType oi of
               TypeScheme (_ : _) _ _ -> Set.insert i s
               _ -> s) Set.empty l) . Map.toList .
            Map.filterWithKey ( \ (Id _ cs _) _ -> null cs)

getCompound :: Id -> [Id]
getCompound (Id _ cs _) = cs

getCompoundLists :: Env -> Set.Set [Id]
getCompoundLists e = Set.delete [] $ Set.map getCompound $ Set.union
    (Map.keysSet $ assumps e) $ Map.keysSet $ typeMap e

uTok :: Token
uTok = mkSimpleId "_"

builtinIds :: [Id]
builtinIds = [unitId, parenId, tupleId, exprId, typeId, applId]

makeRules :: GlobalAnnos -> (PrecMap, Set.Set Id) -> Set.Set Id
          -> Set.Set Id -> (Token -> [Rule], Rules, Set.Set Id)
makeRules ga ps@(p, _) polyIds aIds =
    let (sIds, ids) = Set.partition isSimpleId aIds
        ks = Set.fold (Set.union . getKnowns) Set.empty ids
        rIds = Set.union ids $ Set.intersection sIds $ Set.map simpleIdToId ks
        m2 = maxWeight p + 2
    in ( \ tok -> if isSimpleToken tok
                     && not (Set.member tok ks)
                         || tok == uTok then
                     [(simpleIdToId tok, m2, [tok])] else []
       , partitionRules $ listRules m2 ga ++
             initRules ps (Set.toList polyIds) builtinIds (Set.toList rIds)
       , sIds)

initRules :: (PrecMap, Set.Set Id) -> [Id] -> [Id] -> [Id] -> [Rule]
initRules (p, ps) polyIds bs is =
    map ( \ i -> mixRule (getIdPrec p ps i) i)
            (bs ++ is) ++
    map ( \ i -> (protect i, maxWeight p + 3, getPlainTokenList i))
            (filter isMixfix is) ++
-- identifiers with a positive number of type arguments
    map ( \ i -> let j = polyId i in
        (j, getIdPrec p ps i, getTokenPlaceList j)) polyIds ++
    map ( \ i -> let j = polyId i in
        (protect j, maxWeight p + 3, getPlainTokenList j))
            (filter isMixfix polyIds)

polyId :: Id -> Id
polyId (Id ts _ ps) = let (toks, pls) = splitMixToken ts in
    Id (toks ++ [typeInstTok] ++ pls) [] ps

unPolyId :: Id -> Maybe Id
unPolyId (Id ts cs ps) = let (ft, rt) = partition (== typeInstTok) ts in
    case ft of
      [_] -> Just $ Id rt cs ps
      _ -> Nothing

-- create fresh type vars for unknown ids tagged with type MixfixType [].
anaPattern :: Set.Set Id -> Pattern -> State Env Pattern
anaPattern s pat = case pat of
    QualVar vd -> do newVd <- checkVarDecl vd
                     return $ QualVar newVd
    ResolvedMixTerm i pats ps | null pats &&
        (isSimpleId i || i == simpleIdToId uTok) &&
        not (Set.member i s) -> do
            (tvar, c) <- toEnvState $ freshVar $ posOfId i
            return $ QualVar $ VarDecl i (TypeName tvar rStar c) Other ps
        | otherwise -> do
            l <- mapM (anaPattern s) pats
            return $ ResolvedMixTerm i l ps
    ApplTerm p1 p2 ps -> do
         p3 <- anaPattern s p1
         p4 <- anaPattern s p2
         return $ ApplTerm p3 p4 ps
    TupleTerm pats ps -> do
         l <- mapM (anaPattern s) pats
         return $ TupleTerm l ps
    TypedTerm p q ty ps -> do
         case p of
             QualVar (VarDecl v (MixfixType []) ok qs) ->
                 let newVd = VarDecl v ty ok (qs `appRange` ps) in
                 return $ QualVar newVd
             _ -> do newP <- anaPattern s p
                     return $ TypedTerm newP q ty ps
    AsPattern vd p2 ps -> do
         newVd <- checkVarDecl vd
         p4 <- anaPattern s p2
         return $ AsPattern newVd p4 ps
    _ -> return pat
    where checkVarDecl vd@(VarDecl v t ok ps) = case t of
            MixfixType [] -> do
                (tvar, c) <- toEnvState $ freshVar $ posOfId v
                return $ VarDecl v (TypeName tvar rStar c) ok ps
            _ -> return vd
