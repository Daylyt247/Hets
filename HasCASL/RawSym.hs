{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable
    
  raw symbols bridge symb items and the symbols of a signature
-}

module HasCASL.RawSym where

import HasCASL.As
import HasCASL.Le
import HasCASL.PrintLe()
import HasCASL.TypeAna
import HasCASL.VarDecl
import HasCASL.Builtin
import Common.Id
import Common.Result
import Common.PrettyPrint
import Common.Lib.State
import qualified Common.Lib.Map as Map

statSymbMapItems :: [SymbMapItems] -> Result RawSymbolMap
statSymbMapItems sl = do 
    rs <- mapM ( \ (SymbMapItems kind l _ _)
                 -> mapM (symbOrMapToRaw kind) l) sl
    foldr ( \ (r1, r2) mm -> do
            m <- mm
            if Map.member r1 m then do 
                Result [Diag Error ("duplicate mapping for: " ++ 
                          showPretty r1 "\n ignoring: " ++ showPretty r2 "")
                       $ posOfId $ rawSymName r2] $ Just ()
                return m
              else return $ Map.insert r1 r2 m) 
          (return Map.empty) $ concat rs
 
symbOrMapToRaw :: SymbKind -> SymbOrMap -> Result (RawSymbol, RawSymbol)
symbOrMapToRaw k (SymbOrMap s mt _) = do
    s1 <- symbToRaw k s  
    s2 <- symbToRaw k $ case mt of Nothing -> s
                                   Just t -> t
    return (s1, s2)

statSymbItems :: [SymbItems] -> Result [RawSymbol]
statSymbItems sl = do rs <- mapM (\ (SymbItems kind l _ _) 
                                  -> mapM (symbToRaw kind) l) sl
                      return $ concat rs

symbToRaw :: SymbKind -> Symb -> Result RawSymbol
symbToRaw k (Symb idt mt _)     = case mt of 
    Nothing -> return $ symbKindToRaw k idt
    Just (SymbType sc@(TypeScheme vs t _)) -> 
        let r = return $ AQualId idt $ OpAsItemType sc
            rk = if null vs then Nothing else 
                 convTypeToKind t 
            rrk = maybeToResult (getMyPos t) 
                           ("not a kind: " ++ showPretty t "") rk
        in case k of 
              SK_op -> r
              SK_fun -> r
              SK_pred -> return $ AQualId idt $ OpAsItemType
                         $ predTypeScheme sc
              SK_class -> do ck <- rrk
                             return $ AQualId idt $ ClassAsItemType ck
              _ -> do ck <- rrk
                      return $ AQualId idt $ TypeAsItemType ck

convTypeToKind :: Type -> Maybe Kind
convTypeToKind (FunType t1 FunArr t2 ps) = 
    do k1 <- convTypeToKind t1
       k2 <- convTypeToKind t2
       case k2 of 
               ExtKind _ _ _ -> Nothing
               _ -> Just $ FunKind k1 k2 ps

convTypeToKind (BracketType Parens [] _) = 
    Nothing
convTypeToKind (BracketType Parens [t] _) = 
    convTypeToKind t
convTypeToKind (BracketType Parens ts ps) = 
       do ks <- mapM convTypeToKind ts
          Just $ Intersection ks ps

convTypeToKind (MixfixType [t1, TypeToken t]) = 
    let s = tokStr t 
        mv = case s of 
                   "+" -> Just CoVar 
                   "-" -> Just ContraVar 
                   _ -> Nothing
    in case mv of 
              Nothing -> Nothing
              Just v -> do k1 <- convTypeToKind t1
                           Just $ ExtKind k1 v [tokPos t]
convTypeToKind (TypeToken t) = 
       if tokStr t == "Type" then Just $ Intersection [] [tokPos t] else
          let ci = simpleIdToId t in
          Just $ ClassKind ci MissingKind
convTypeToKind _ = Nothing

matchSymb :: Symbol -> RawSymbol -> Bool
matchSymb sy rsy = let ty = symType sy in 
    (&&) (symName sy == rawSymName rsy) $ 
       case rsy of 
                AnID _ -> True
                AKindedId k _ -> symbTypeToKind ty == k
                AQualId _ _ -> maybe False (matchSymb sy) $ 
                               maybeResult $ matchQualId (symEnv sy) rsy
                ASymbol s -> ty == symType s

anaSymbolType :: SymbolType -> State Env (Maybe SymbolType)
anaSymbolType t = 
    case t of 
    ClassAsItemType k -> do ak <- fromResult $ anaKindM k
                            return $ fmap ClassAsItemType ak
    TypeAsItemType k -> do ak <- fromResult $ anaKindM k
                           return $ fmap TypeAsItemType ak
    OpAsItemType sc -> do as <- anaTypeScheme sc
                          return $ fmap OpAsItemType as 

instance PosItem RawSymbol where
    get_pos rsy = Just $ posOfId $ rawSymName rsy

matchQualId :: Env -> RawSymbol -> Result RawSymbol
matchQualId e rsy = 
       case rsy of 
       AQualId i t -> 
           let mt = evalState (anaSymbolType t) e 
                    {typeMap = addUnit $ typeMap e}
           in case mt of 
              Nothing -> Result 
                  [mkDiag Error "non-matching qualified symbol" rsy] Nothing
              Just ty -> return $ ASymbol $ Symbol i ty e
       _ -> return rsy

anaRawMap :: Env -> Env -> RawSymbolMap -> Result RawSymbolMap
anaRawMap s1 s2 = 
    Map.foldWithKey ( \ i v rm -> do
            m <- rm
            j <- matchQualId s1 i
            w <- matchQualId s2 v
            case Map.lookup j m of 
                Nothing -> return $ Map.insert j w m
                Just x -> Result [mkDiag Error "duplicate mapping for" i,
                                 mkDiag Hint ("mapped to '" 
                                  ++ showPretty x "' and '" 
                                  ++ showPretty w "' from") j] Nothing)
                      $ return Map.empty
