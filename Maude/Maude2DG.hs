import System.IO
import System.Environment
import System.Process

import Static.DevGraph
import Static.GTheory
import Static.AnalysisStructured

import Logic.Prover
import Logic.Grothendieck
import Logic.ExtSign
import Logic.Logic

import Maude.AS_Maude
import Maude.Sign
import Maude.Printing
import Maude.Sentence
import Maude.Morphism
import Maude.Logic_Maude
import Maude.Language 
import qualified Maude.Meta.HasName as HasName

import Data.Maybe
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Graph.Inductive.Graph

import Common.AS_Annotation
import Common.Result
import Common.Id

-- Borrar despues de las pruebas
import GUI.ShowGraph
import Driver.Options
import Common.LibName

maude_cmd :: String
maude_cmd = "/Applications/maude-darwin/maude.intelDarwin -interactive -no-banner"

data ImportType = Pr | Ex | Inc
type ModExpProc = (Token, TokenInfoMap, Morphism, DGraph)
type ImportProc = (ImportType, Token, TokenInfoMap, Morphism, DGraph)
type TokenInfoMap = Map.Map Token ProcInfo
type ProcInfo = (Node, Sign, [Token], [(Token, Token, [Token])], [ParamSort])
type ParamInfo = ([(Token, Token, [Token])], TokenInfoMap, [Morphism], DGraph)

-- | Map from view identifiers to tuples containing the target node of the
-- view, the morphism, and a Boolean value indicating if the view instantiates
-- all the values
type ViewMap = Map.Map Token (Node, Morphism, Bool)

type InsSpecRes = (TokenInfoMap, ViewMap, [Token], DGraph)

-- | Pair of tokens and parameters contained by the token
type ParamSort = (Token, [Token])

insertSpecs :: [Spec] -> TokenInfoMap -> ViewMap -> [Token] -> DGraph -> DGraph
insertSpecs [] _ _ _ dg = dg
insertSpecs (s : ss) tim vm ths dg = insertSpecs ss tim' vm' ths' dg'
              where (tim', vm', ths', dg') = insertSpec s tim vm ths dg

insertSpec :: Spec -> TokenInfoMap -> ViewMap -> [Token] -> DGraph -> InsSpecRes
insertSpec (SpecMod sp_mod) tim vm ths dg = (tim4, vm, ths, dg5)
              where ps = getParams sp_mod
                    (pl, tim1, morphs, dg1) = processParameters ps tim dg
                    top_sg = fromSpec sp_mod
                    paramSorts = getSortsParameterizedBy (paramNames ps) (Set.toList $ sorts top_sg)
                    (il, _) = getImportsSorts sp_mod
                    ips = processImports tim1 vm dg1 il
                    (tim2, dg2) = last_da ips (tim1, dg1)
                    sg = sign_union_morphs morphs $ sign_union top_sg ips
                    ext_sg = makeExtSign Maude sg
                    nm_sns = map (makeNamed "") $ getSentences sp_mod
                    sens = toThSens nm_sns
                    gt = G_theory Maude ext_sg startSigId sens startThId
                    tok = HasName.getName sp_mod
                    name = makeName tok
                    (ns, dg3) = insGTheory dg2 name DGBasic gt
                    tim3 = Map.insert tok (getNode ns, sg, [], pl, paramSorts) tim2
                    (tim4, dg4) = createEdgesImports tok ips sg tim3 dg3
                    dg5 = createEdgesParams tok pl morphs sg tim4 dg4
insertSpec (SpecTh sp_th) tim vm ths dg = (tim3, vm, tok : ths, dg3)
              where (il, ss1) = getImportsSorts sp_th
                    ips = processImports tim vm dg il
                    ss2 = getThSorts ips
                    (tim1, dg1) = last_da ips (tim, dg)
                    sg = sign_union (fromSpec sp_th) ips
                    ext_sg = makeExtSign Maude sg
                    nm_sns = map (makeNamed "") $ getSentences sp_th
                    sens = toThSens nm_sns
                    gt = G_theory Maude ext_sg startSigId sens startThId
                    tok = HasName.getName sp_th
                    name = makeName tok
                    (ns, dg2) = insGTheory dg1 name DGBasic gt
                    tim2 = Map.insert tok (getNode ns, sg, ss1 ++ ss2, [], []) tim1
                    (tim3, dg3) = createEdgesImports tok ips sg tim2 dg2
insertSpec (SpecView sp_v) tim vm ths dg = (tim2, vm', ths, dg4)
              where View name from to rnms = sp_v
                    inst = isInstantiated ths to
                    tok_name = HasName.getName name
                    (tok1, tim1, morph1, dg1) = processModExp tim vm dg from
                    (tok2, tim2, morph2, dg2) = processModExp tim1 vm dg1 to
                    (n1, _, _, _, _) = fromJust $ Map.lookup tok1 tim2
                    (n2, _, _, _, _) = fromJust $ Map.lookup tok2 tim2
                    morph = fromSignsRenamings (target morph1) (target morph2) rnms
                    morph' = fromJust $ maybeResult $ compose morph1 morph
                    (new_sign, new_sens) = sign4renamings (target morph1) (sortMap morph) rnms
                    (n3, dg3) = insertInnerNode n2 (makeName tok2) morph2 new_sign new_sens dg2
                    vm' = Map.insert (HasName.getName name) (n3, morph', inst) vm
                    dg4 = insertThmEdgeMorphism tok_name n3 n1 morph' dg3

-- | compute the union of the signatures obtained from the importation list
sign_union :: Sign -> [ImportProc] -> Sign
sign_union sign = foldr (Maude.Sign.union . get_sign) sign

-- | extract the target signature from the morphism in an importation tuple
get_sign :: ImportProc -> Sign
get_sign (_, _, _, morph, _) = target morph

-- | compute the union of the target signatures of a list of morphisms
sign_union_morphs :: [Morphism] -> Sign -> Sign
sign_union_morphs morphs sg =  foldr (Maude.Sign.union . target) sg morphs

-- | extracts the last (newest) data structures from a list of importation
-- tuples, using the second argument as default value if the list is empty
last_da :: [ImportProc] -> (TokenInfoMap, DGraph) -> (TokenInfoMap, DGraph)
last_da [(_, _, tim, _, dg)] _ = (tim, dg)
last_da (_ : ips) p = last_da ips p
last_da _ p = p

-- | generate the edges required by a parameter list in a module instantiation
createEdgesParams :: Token -> [(Token, Token, [Token])] -> [Morphism] -> Sign
                     -> TokenInfoMap -> DGraph -> DGraph
createEdgesParams tok1 ((_, tok2, _) : toks) (morph : morphs) sg tim dg =
                                       createEdgesParams tok1 toks morphs sg tim dg'
               where morph' = setTarget sg morph
                     (n1, _, _, _, _) = fromJust $ Map.lookup tok1 tim
                     (n2, _, _, _, _) = fromJust $ Map.lookup tok2 tim
                     dg' = insertDefEdgeMorphism n1 n2 morph' dg
createEdgesParams _ _ _ _ _ dg = dg

-- | generate the edges required by the importations
createEdgesImports :: Token -> [ImportProc] -> Sign -> TokenInfoMap -> DGraph
                      -> (TokenInfoMap, DGraph)
createEdgesImports _ [] _ tim dg = (tim, dg)
createEdgesImports tok (ip : ips) sg tim dg = createEdgesImports tok ips sg tim' dg'
               where (tim', dg') = createEdgeImport tok ip sg tim dg

-- | generate the edge for a concrete importation
createEdgeImport :: Token -> ImportProc -> Sign -> TokenInfoMap -> DGraph
                    -> (TokenInfoMap, DGraph)
createEdgeImport tok1 (Pr, tok2, _, morph, _) sg tim dg = (tim', dg'')
               where morph' = setTarget sg morph
                     (tok2', tim', dg') = insertFreeNode tok2 tim dg
                     (n1, _, _, _, _) = fromJust $ Map.lookup tok1 tim'
                     (n2, _, _, _, _) = fromJust $ Map.lookup tok2' tim'
                     dg'' = insertDefEdgeMorphism n1 n2 morph' dg'
createEdgeImport tok1 (Ex, tok2, _, morph, _) sg tim dg = (tim, dg')
               where morph' = setTarget sg morph
                     (n1, _, _, _, _) = fromJust $ Map.lookup tok1 tim
                     (n2, _, _, _, _) = fromJust $ Map.lookup tok2 tim
                     dg' = insertConsEdgeMorphism n1 n2 morph' dg
createEdgeImport tok1 (Inc, tok2, _, morph, _) sg tim dg = (tim, dg')
               where morph' = setTarget sg morph
                     (n1, _, _, _, _) = fromJust $ Map.lookup tok1 tim
                     (n2, _, _, _, _) = fromJust $ Map.lookup tok2 tim
                     dg' = insertDefEdgeMorphism n1 n2 morph' dg

getThSorts :: [ImportProc] -> [Token]
getThSorts [] = []
getThSorts (ip : ips) = getThSortsAux ip ++ getThSorts ips

getThSortsAux :: ImportProc -> [Token]
getThSortsAux (_, tok, tim, _, _) = srts
         where (_, _, srts, _, _) = fromJust $ Map.lookup tok tim

-- | generate the extra signature needed when using term to term renaming in views
sign4renamings :: Sign -> Map.Map Token Token -> [Renaming] -> (Sign, [Sentence])
sign4renamings sg mtt ((TermMap t1 t2) : rnms) = (new_sg, (Equation eq) : sens)
         where (op_top, ss) = getOpSorts t1
               sg' = newOp sg op_top ss mtt
               (sg'', sens) = sign4renamings sg mtt rnms
               eq = Eq (applyRenamingTerm mtt t1) t2 [] []
               new_sg = Maude.Sign.union sg' sg''
sign4renamings sg mtt (_ : rnms) = sign4renamings sg mtt rnms
sign4renamings sg _ [] = (sg, [])

-- | given the identifier of an operator in the given signature, the function
-- generates a new signature with this operator and a renamed profile computed
-- from the renaming given in the mapping
newOp :: Sign -> Token -> [Token] -> Map.Map Token Token -> Sign
newOp sg op ss mtt = Maude.Sign.empty {ops = Map.singleton op $ Set.singleton od}
         where om = ops sg
               ods = fromJust $ Map.lookup op om
               od = getOpDecl ods ss mtt

-- | rename the profile with the given map
getOpDecl :: OpDeclSet -> [Token] -> Map.Map Token Token -> OpDecl
getOpDecl ods ss mtt = od'
         where f = \ (x, _, _) -> x == ss
               od : _ = Set.toList $ Set.filter f ods
               od' = applyRenamingOD od mtt

-- | apply the renaming in the map to the operator declaration
applyRenamingOD :: OpDecl -> Map.Map Token Token -> OpDecl
applyRenamingOD (ar, co, ats) mtt = (ar', co', ats)
         where f = \ x -> if Map.member x mtt
                          then fromJust $ Map.lookup co mtt
                          else x
               ar' = map f ar
               co' = if Map.member co mtt
                     then fromJust $ Map.lookup co mtt
                     else co

-- | rename the sorts in a term
applyRenamingTerm :: Map.Map Token Token -> Term -> Term
applyRenamingTerm mtt (Apply q ts ty) = Apply q (map (applyRenamingTerm mtt) ts)
                                                (applyRenamingType mtt ty)
applyRenamingTerm mtt (Const q s) = Const q s'
         where s' = applyRenamingType mtt s
applyRenamingTerm mtt (Var q s) = Var q s'
         where s' = applyRenamingType mtt s

-- | rename a type
applyRenamingType :: Map.Map Token Token -> Type -> Type
applyRenamingType mtt (TypeSort s) = TypeSort $ SortId q'
         where SortId q = s
               q' = if Map.member q mtt
                    then fromJust $ Map.lookup q mtt
                    else q
applyRenamingType mtt (TypeKind k) = TypeKind $ KindId q'
         where KindId q = k
               q' = if Map.member q mtt
                    then fromJust $ Map.lookup q mtt
                    else q

-- | extract the top operator of a term and the names of its sorts
-- if it is applicated to some arguments
getOpSorts :: Term -> (Token, [Token])
getOpSorts (Const q _) = (q, [])
getOpSorts (Var q _) = (q, [])
getOpSorts (Apply q ls _) = (q, getTypes ls)

getTypes :: [Term] -> [Token]
getTypes ((Var _ s) : ts) = HasName.getName s : getTypes ts
getTypes _ = []

processImports :: TokenInfoMap -> ViewMap -> DGraph -> [Import] -> [ImportProc]
processImports _ _ _ [] = []
processImports tim vm dg (i : il) = ip : processImports tim' vm dg' il
         where ip@(_, _, tim', _, dg') = processImport tim vm dg i

processImport :: TokenInfoMap -> ViewMap -> DGraph -> Import -> ImportProc
processImport tim vm dg (Protecting modExp) = (Pr, tok, tim', morph, dg')
         where (tok, tim', morph, dg') = processModExp tim vm dg modExp
processImport tim vm dg (Extending modExp) = (Ex, tok, tim', morph, dg')
         where (tok, tim', morph, dg') = processModExp tim vm dg modExp
processImport tim vm dg (Including modExp) = (Inc, tok, tim', morph, dg')
         where (tok, tim', morph, dg') = processModExp tim vm dg modExp

processParameters :: [Parameter] -> TokenInfoMap -> DGraph -> ParamInfo
processParameters ps tim dg = foldr processParameter ([], tim, [], dg) ps

processParameter :: Parameter -> ParamInfo -> ParamInfo
processParameter (Parameter sort modExp) (toks, tim, morphs, dg) = (toks', tim', morphs', dg')
         where (tok, tim', morph, dg') = processModExp tim Map.empty dg modExp
               (_, _, fs, _, _) = fromJust $ Map.lookup tok tim'
               fs' = renameSorts morph fs
               morph' = extendMorphismSorts morph (HasName.getName sort) fs'
               toks' = (HasName.getName sort, tok, fs') : toks
               morphs' =  morph' : morphs

processModExp :: TokenInfoMap -> ViewMap -> DGraph -> ModExp -> ModExpProc
processModExp tim _ dg (ModExp modId) = (tok, tim, morph, dg)
                     where tok = HasName.getName modId
                           (_, sg, _, _, _) = fromJust $ Map.lookup tok tim
                           morph = createInclMorph sg sg
processModExp tim vm dg (SummationModExp modExp1 modExp2) = (tok, tim3, morph, dg5)
                     where (tok1, tim1, morph1, dg1) = processModExp tim vm dg modExp1
                           (tok2, tim2, morph2, dg2) = processModExp tim1 vm dg1 modExp2
                           tok = mkSimpleId $ "{" ++ show tok1 ++ " + " ++ show tok2 ++ "}"
                           (n1, _, ss1, _, _) = fromJust $ Map.lookup tok1 tim2
                           (n2, _, ss2, _, _) = fromJust $ Map.lookup tok2 tim2
                           ss1' = renameSorts morph1 ss1
                           ss2' = renameSorts morph1 ss2
                           sg1 = target morph1
                           sg2 = target morph2
                           sg = Maude.Sign.union sg1 sg2
                           morph = createInclMorph sg sg
                           morph1' = setTarget sg morph1
                           morph2' = setTarget sg morph2
                           (tim3, dg3) = insertNode tok sg tim2 (ss1' ++ ss2') dg2
                           (n3, _, _, _, _) = fromJust $ Map.lookup tok tim3
                           dg4 = insertDefEdgeMorphism n3 n1 morph1' dg3
                           dg5 = insertDefEdgeMorphism n3 n2 morph2' dg4
processModExp tim vm dg (RenamingModExp modExp rnms) = (tok, tim', comp_morph, dg')
                     where (tok, tim', morph, dg') = processModExp tim vm dg modExp
                           morph' = fromSignRenamings (target morph) rnms
                           comp_morph = fromJust $ maybeResult $ compose morph morph'
processModExp tim vm dg (InstantiationModExp modExp views) = (tok'', tim'', morph'', dg'')
                     where (tok, tim', morph, dg') = processModExp tim vm dg modExp
                           (_, _, _, ps, _) = fromJust $ Map.lookup tok tim'
                           (tok', morph', ns) = processViews views (mkSimpleId "") tim' vm ps (Maude.Morphism.empty, [])
                           tok'' = mkSimpleId $ show tok ++ "{" ++ show tok' ++ "}"
                           morph'' = Maude.Morphism.union morph morph'
                           sg2 = target morph''
                           (tim'', dg'') = if Map.member tok'' tim
                                           then (tim', dg')
                                           else updateGraphViews tok tok'' sg2 morph' ns tim' dg'

updateGraphViews :: Token -> Token -> Sign -> Morphism -> [(Node, Sign)] -> TokenInfoMap -> DGraph
                    -> (TokenInfoMap, DGraph)
updateGraphViews tok1 tok2 sg morph views tim dg = (tim', dg''')
                     where (n1, _, _, _, _) = fromJust $ Map.lookup tok1 tim
                           morph' = setTarget sg morph
                           -- TODO: if the parameter is another theory, the empty list
                           -- must be replaced by the corresponding list of sorts
                           (tim', dg') = insertNode tok2 sg tim [] dg
                           (n2, _, _, _, _) = fromJust $ Map.lookup tok2 tim'
                           dg'' = insertDefEdgeMorphism n2 n1 morph' dg'
                           dg''' = insertDefEdgesMorphism n2 views sg dg''

insertDefEdgesMorphism :: Node -> [(Node, Sign)] -> Sign -> DGraph -> DGraph
insertDefEdgesMorphism _ [] _ dg = dg
insertDefEdgesMorphism n1 ((n2, sg1) : views) sg2 dg = insertDefEdgesMorphism n1 views sg2 dg'
                  where morph = createInclMorph sg1 sg2
                        dg' = insertDefEdgeMorphism n1 n2 morph dg

processViews :: [ViewId] -> Token -> TokenInfoMap -> ViewMap -> [(Token, Token, [Token])]
                -> (Morphism, [(Node, Sign)]) -> (Token, Morphism, [(Node, Sign)])
processViews (vi : vis) tok tim vm (p : ps) (morph, lp) =
                             case mn of
                                   Just n -> processViews vis tok'' tim vm ps (morph'', lp ++ [(n, target morph')])
                                   Nothing -> processViews vis tok'' tim vm ps (morph'', lp)
                     where (tok', morph', mn) = processView vi tok tim vm p
                           tok'' = mkSimpleId $ show tok ++ ", " ++ show tok'
                           morph'' = Maude.Morphism.union morph morph'
processViews _ tok _ _ _ (morph, nds) = (tok', morph, nds)
                     where tok' = mkSimpleId $ drop 2 $ show tok

processView :: ViewId -> Token -> TokenInfoMap -> ViewMap -> (Token, Token, [Token])
               -> (Token, Morphism, Maybe Node)
processView vi tok tim vm (p, _, ss) =
                       if Map.member name vm
                       then morphismView name p ss $ fromJust $ Map.lookup name vm
                       else morphismView name p ss $ fromJust $ Map.lookup name vm
        where name = HasName.getName vi

morphismView :: Token -> Token -> [Token] -> (Node, Morphism, Bool)
                -> (Token, Morphism, Maybe Node)
morphismView name p ss (n, morph, _) = (name, morph', Just n)
        where morph' = addQualification morph p ss

insertNode :: Token -> Sign -> TokenInfoMap -> [Token] -> DGraph -> (TokenInfoMap, DGraph)
insertNode tok sg tim ss dg = if Map.member tok tim
                         then (tim, dg)
                         else let
                                ext_sg = makeExtSign Maude sg
                                gt = G_theory Maude ext_sg startSigId noSens startThId
                                name = makeName tok
                                (ns, dg') = insGTheory dg name DGBasic gt
                                tim' = Map.insert tok (getNode ns, sg, ss, [], []) tim
                              in (tim', dg')

insertInnerNode :: Node -> NodeName -> Morphism -> Sign -> [Sentence] -> DGraph
                   -> (Node, DGraph)
insertInnerNode nod nm morph sg sens dg =
                         if (isIdentity morph) && (sens == [])
                         then (nod, dg)
                         else let
                                th_sens = toThSens $ map (makeNamed "") sens
                                sg' = Maude.Sign.union sg $ target morph
                                ext_sg = makeExtSign Maude sg'
                                gt = G_theory Maude ext_sg startSigId th_sens startThId
                                (ns, dg') = insGTheory dg (inc nm) DGBasic gt
                                nod2 = getNode ns
                                morph' = setTarget sg' morph
                                dg'' = insertDefEdgeMorphism nod2 nod morph' dg'
                              in (nod2, dg'')

insertDefEdgeMorphism :: Node -> Node -> Morphism -> DGraph -> DGraph
insertDefEdgeMorphism n1 n2 morph dg = insEdgeDG (n2, n1, edg) dg
                     where mor = G_morphism Maude morph startMorId
                           edg = DGLink (gEmbed mor) globalDef SeeTarget $ getNewEdgeId dg

insertThmEdgeMorphism :: Token -> Node -> Node -> Morphism -> DGraph -> DGraph
insertThmEdgeMorphism name n1 n2 morph dg = insEdgeDG (n2, n1, edg) dg
                     where mor = G_morphism Maude morph startMorId
                           edg = DGLink (gEmbed mor) globalThm (DGLinkView name) $ getNewEdgeId dg

insertConsEdgeMorphism :: Node -> Node -> Morphism -> DGraph -> DGraph
insertConsEdgeMorphism n1 n2 morph dg = insEdgeDG (n2, n1, edg) dg
                     where mor = G_morphism Maude morph startMorId
                           edg = DGLink (gEmbed mor) (globalConsThm PCons) SeeTarget $ getNewEdgeId dg

insertFreeEdge :: Token -> Token -> TokenInfoMap -> DGraph -> DGraph
insertFreeEdge tok1 tok2 tim dg = insEdgeDG (n2, n1, edg) dg
                     where (n1, sg1, _, _, _) = fromJust $ Map.lookup tok1 tim
                           (n2, sg2, _, _, _) = fromJust $ Map.lookup tok2 tim
                           mor = G_morphism Maude (createInclMorph sg1 sg2) startMorId
                           dgt = FreeOrCofreeDefLink Free $ EmptyNode (Logic Maude)
                           edg = DGLink (gEmbed mor) dgt SeeTarget $ getNewEdgeId dg

insertFreeNode :: Token -> TokenInfoMap -> DGraph -> (Token, TokenInfoMap, DGraph)
insertFreeNode t tim dg = (t', tim', dg'')
               where t' = mkFreeName t
                     b = Map.member t' tim
                     (tim', dg') = if b
                                   then (tim, dg)
                                   else insertFreeNode2 t' tim (fromJust $ Map.lookup t tim) dg
                     dg'' = if b
                            then dg'
                            else insertFreeEdge t' t tim' dg'

insertFreeNode2 :: Token -> TokenInfoMap -> ProcInfo -> DGraph -> (TokenInfoMap, DGraph)
insertFreeNode2 t tim (_, sg, _, _, _) dg = (tim', dg')
              where ext_sg = makeExtSign Maude sg
                    gt = G_theory Maude ext_sg startSigId noSens startThId
                    name = makeName t
                    (ns, dg') = insGTheory dg name DGBasic gt
                    tim' = Map.insert t (getNode ns, sg, [], [], []) tim

-- | Given the identifier of a module, generates the identifier for the module
-- with the ``freeness'' constraint
mkFreeName :: Token -> Token
mkFreeName = mkSimpleId . (\ x -> x ++ "'") . show

getParams :: Module -> [Parameter]
getParams (Module _ params _) = params

getImportsSorts :: Module -> ([Import], [Token])
getImportsSorts (Module _ _ stmts) = getImportsSortsStmnts stmts ([],[])

getImportsSortsStmnts :: [Statement] -> ([Import], [Token]) -> ([Import], [Token])
getImportsSortsStmnts [] p = p
getImportsSortsStmnts ((ImportStmnt imp) : stmts) (is, ss) =
                                  getImportsSortsStmnts stmts (imp : is, ss)
getImportsSortsStmnts ((SortStmnt s) : stmts) (is, ss) =
            getImportsSortsStmnts stmts (is, (HasName.getName s) : ss)
getImportsSortsStmnts (_ : stmts) p = getImportsSortsStmnts stmts p

directMaudeParsing :: FilePath -> IO DGraph
directMaudeParsing fp = do
              (hIn, hOut, _, _) <- runInteractiveCommand maude_cmd
              hPutStrLn hIn $ "load " ++ fp
              ns <- parse fp
              let ns' = either (\ _ -> []) id ns
              ms <- traverseNames hIn hOut ns'
              hPutStrLn hIn "in Maude/hets.prj"
              psps <- predefinedSpecs hIn hOut
              sps <- traverseSpecs hIn hOut ms
              hClose hIn
              hClose hOut
              return $ insertSpecs (psps ++ sps) Map.empty Map.empty [] emptyDG

main :: IO ()
main = getArgs >>= mapM_ directMaudeParsing2

directMaudeParsing2 :: FilePath -> IO ()
directMaudeParsing2 fp = do
    dg <- directMaudeParsing fp
    showGraph fp maudeHetcatsOpts
              (Just (Lib_id (Direct_link "" nullRange),
              Map.singleton (Lib_id (Direct_link "" nullRange)) dg ))

traverseSpecs :: Handle -> Handle -> [String] -> IO [Spec]
traverseSpecs _ _ [] = return []
traverseSpecs hIn hOut (m : ms) = do
                 hPutStrLn hIn m
                 hFlush hIn
                 sOutput <- getAllSpec hOut "" False
                 ss <- traverseSpecs hIn hOut ms
                 let stringSpec = getSpec sOutput
                 let spec = read stringSpec :: Spec
                 return $ spec : ss

traverseNames :: Handle -> Handle -> [NamedSpec] -> IO [String]
traverseNames _ _ [] = return []
traverseNames hIn hOut (ModName q : ns) = do
                 hPutStrLn hIn $ "show module " ++ q ++ " ."
                 hFlush hIn
                 sOutput <- getAllOutput hOut "" False
                 rs <- traverseNames hIn hOut ns
                 return $ sOutput : rs
traverseNames hIn hOut (ViewName q : ns) = do
                 hPutStrLn hIn $ "show view " ++ q ++ " ."
                 hFlush hIn
                 sOutput <- getAllOutput hOut "" False
                 rs <- traverseNames hIn hOut ns
                 return $ sOutput : rs

getAllOutput :: Handle -> String -> Bool -> IO String
getAllOutput hOut s False = do
                 ss <- hGetLine hOut
                 getAllOutput hOut (s ++ " " ++ ss) (final ss)
getAllOutput _ s True = return $ prepare s

getAllSpec :: Handle -> String -> Bool -> IO String
getAllSpec hOut s False = do
                 ss <- hGetLine hOut
                 getAllSpec hOut (s ++ " " ++ ss) (finalSpec ss)
getAllSpec _ s True = return s

final :: String -> Bool
final "endfm" = True
final "endm" = True
final "endth" = True
final "endfth" = True
final "endv" = True
final _ = False

prepare :: String -> String
prepare s = "(" ++ (drop 8 s) ++ ")"

finalSpec :: String -> Bool
finalSpec "@#$endHetsSpec$#@" = True
finalSpec _ = False

predefined :: [NamedSpec]
predefined = [ModName "TRUTH-VALUE", ModName "TRUTH", ModName "BOOL", ModName "EXT-BOOL",
              ModName "NAT",
              ModName "INT", ModName "RAT", ModName "FLOAT", ModName "STRING", ModName "CONVERSION",
              ModName "RANDOM", ModName "QID", ModName "TRIV", ViewName "TRIV", ViewName "Bool",
              ViewName "Nat", ViewName "Int", ViewName "Rat", ViewName "Float", ViewName "String",
              ViewName "Qid", ModName "STRICT-WEAK-ORDER", ViewName "STRICT-WEAK-ORDER",
              ModName "STRICT-TOTAL-ORDER", ViewName "STRICT-TOTAL-ORDER", ViewName "Nat<",
              ViewName "Int<", ViewName "Rat<", ViewName "Float<", ViewName "String<",
              ModName "TOTAL-PREORDER", ViewName "TOTAL-PREORDER", ModName "TOTAL-ORDER", 
              ViewName "TOTAL-ORDER", ViewName "Nat<=", ViewName "Int<=", ViewName "Rat<=",
              ViewName "Float<=", ViewName "String<=", ModName "DEFAULT", ViewName "DEFAULT",
              ViewName "Nat0", ViewName "Int0", ViewName "Rat0", ViewName "Float0",
              ViewName "String0", ViewName "Qid0", ModName "LIST"]

predefinedSpecs :: Handle -> Handle -> IO [Spec]
predefinedSpecs hIn hOut = traversePredefined hIn hOut predefined

traversePredefined :: Handle -> Handle -> [NamedSpec] -> IO [Spec]
traversePredefined _ _ [] = return []
traversePredefined hIn hOut (ModName n : ns) = do
                 hPutStrLn hIn $ "(hets " ++ n ++ " .)"
                 hFlush hIn
                 sOutput <- getAllSpec hOut "" False
                 ss <- traversePredefined hIn hOut ns
                 let stringSpec = getSpec sOutput
                 let spec = read stringSpec :: Spec
                 return $ spec : ss
traversePredefined hIn hOut (ViewName n : ns) = do
                 hPutStrLn hIn $ "(hetsView " ++ n ++ " .)"
                 hFlush hIn
                 sOutput <- getAllSpec hOut "" False
                 ss <- traversePredefined hIn hOut ns
                 let stringSpec = getSpec sOutput
                 let spec = read stringSpec :: Spec
                 return $ spec : ss

paramNames :: [Parameter] -> [Token]
paramNames = map f
         where f = \ (Parameter s _) -> HasName.getName s

-- | return the sorts (second argument) that contain any of the parameters
-- given as first argument
getSortsParameterizedBy :: [Token] -> [Token] -> [(Token, [Token])]
getSortsParameterizedBy ps = filter f . map (g ps)
           where f = \ (_, l) -> l /= []
                 g = \ pss x -> let 
                         params = getSortParams x
                         in (x, intersec params pss)
                 

intersec :: [Token] -> [Token] -> [Token]
intersec [] _ = []
intersec (e : es) l = case elem e l of
        False -> intersec es l
        True -> e : intersec es l

-- | extracts the parameters of the given sort
-- For example, getSortParams List{X} = [X]
getSortParams :: Token -> [Token]
getSortParams t = getSortParamsString $ show t

getSortParamsString :: String -> [Token]
getSortParamsString [] = []
getSortParamsString ('{' : cs) = if sps == []
                                 then getSortParamsStringAux cs ""
                                 else sps
            where sps = getSortParamsString cs
getSortParamsString (_ : cs) = getSortParamsString cs

getSortParamsStringAux :: String -> String -> [Token]
getSortParamsStringAux (',' : cs) st = mkSimpleId st : getSortParamsStringAux cs ""
getSortParamsStringAux ('}' : []) st = [mkSimpleId st]
getSortParamsStringAux (' ' : cs) st = getSortParamsStringAux cs st
getSortParamsStringAux (c : cs) st = getSortParamsStringAux cs (st ++ [c])
getSortParamsStringAux [] st = [mkSimpleId st]

-- | check if the target of the view is completely instantiated (to modules)
isInstantiated :: [Token] -> ModExp -> Bool
isInstantiated ths (ModExp modExp) = notElem (HasName.getName modExp) ths
isInstantiated ths (SummationModExp me1 me2) = isInstantiated ths me1 && 
                                               isInstantiated ths me2
isInstantiated ths (RenamingModExp modExp _) = isInstantiated ths modExp
isInstantiated _ (InstantiationModExp _ _) = True

-- DELETE ONCE TESTS ARE FINISHED

maudeHetcatsOpts :: HetcatsOpts
maudeHetcatsOpts = HcOpt
  { analysis = Basic
  , guiType = UseGui
  , infiles  = []
  , specNames = []
  , transNames = []
  , intype   = GuessIn
  , libdir   = ""
  , modelSparQ = ""
  , outdir   = ""
  , outtypes = [] -- no default
  , recurse  = False
  , defLogic = "Maude"
  , verbose  = 1
  , outputToStdout = True
  , caslAmalg = []
  , interactive = False
  , connectP = -1
  , connectH = ""
  , uncolored = False
  , xmlFlag = False
  , computeNormalForm = False
  , dumpOpts = []
  , listen   = -1 }

-- insertNode tiene que recibir tambien la lista de sorts parametrizados que se
-- calculen para la module expression