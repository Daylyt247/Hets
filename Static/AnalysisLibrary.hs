{- |
Module      :  $Header$
Description :  static analysis of CASL specification libraries
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable(Logic)

Static analysis of CASL specification libraries
   Follows the verification semantics sketched in Chap. IV:6
   of the CASL Reference Manual.
-}

module Static.AnalysisLibrary
    ( anaLibFileOrGetEnv
    , anaLibDefn
    , anaSourceFile
    , anaLibItem
    , anaViewDefn
    ) where

import Logic.Logic
import Logic.Grothendieck

import Syntax.AS_Structured
import Syntax.AS_Library

import Static.GTheory
import Static.DevGraph
import Static.ComputeTheory
import Static.AnalysisStructured
import Static.AnalysisArchitecture

import Common.AS_Annotation hiding (isAxiom, isDef)
import Common.GlobalAnnotations
import Common.ConvertGlobalAnnos
import Common.AnalyseAnnos
import Common.Result
import Common.ResultT
import Common.LibName
import Common.Id

import Driver.Options
import Driver.ReadFn
import Driver.WriteLibDefn

import Data.Graph.Inductive.Graph
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.List

import Control.Monad
import Control.Monad.Trans

import Data.Char

import System.Directory
import System.FilePath
import System.Time

-- a set of library names to check for cyclic imports
type LNS = Set.Set LibName

-- | parsing and static analysis for files
-- Parameters: logic graph, default logic, file name
anaSourceFile :: LogicGraph -> HetcatsOpts -> LNS -> LibEnv -> DGraph
  -> FilePath -> ResultT IO (LibName, LibEnv)
anaSourceFile lgraph opts topLns libenv initDG fname = ResultT $ do
  fname' <- findFileOfLibName opts fname
  case fname' of
    Nothing ->
        return $ fail $ "no file for library '" ++ fname ++ "' found."
    Just file ->
        if any (flip isSuffixOf file) [envSuffix, prfSuffix] then
            fail $ "no matching source file for '" ++ fname ++ "' found."
        else do
        input <- readFile file
        mt <- getModificationTime file
        putIfVerbose opts 2 $ "Reading file " ++ file
        runResultT $ anaString lgraph opts topLns libenv initDG input file mt

-- | parsing and static analysis for string (=contents of file)
-- Parameters: logic graph, default logic, contents of file, filename
anaString :: LogicGraph -> HetcatsOpts -> LNS -> LibEnv -> DGraph -> String
          -> FilePath -> ClockTime -> ResultT IO (LibName, LibEnv)
anaString lgraph opts topLns libenv initDG input file mt = do
  curDir <- lift $ getCurrentDirectory -- get full path for parser positions
  let Result ds mast = readLibDefnM lgraph opts (curDir </> file) input mt
  case mast of
    Just pAst@(Lib_defn pln is ps ans) ->
         let libPath = filter (\ c -> isAlphaNum c || elem c "'_/")
               $ dropWhile (== '/') $ rmSuffix file
             nLn = LibName (IndirectLink libPath nullRange file mt) Nothing
             noLibName = null $ show $ getLibId pln
             spN = reverse $ takeWhile (/= '/') $ reverse libPath
             nIs = case is of
               [Annoted (Spec_defn spn gn as qs) rs [] []]
                 | noLibName && null (tokStr spn)
                   -> [Annoted (Spec_defn (mkSimpleId spN) gn as qs) rs [] []]
               _ -> is
             ast@(Lib_defn ln _ _ _) = if noLibName then
               Lib_defn nLn nIs ps ans else pAst
         in case analysis opts of
      Skip  -> do
          lift $ putIfVerbose opts 1 $
                  "Skipping static analysis of library " ++ show ln
          ga <- liftR $ addGlobalAnnos emptyGlobalAnnos ans
          lift $ writeLibDefn ga file opts ast
          liftR $ Result ds Nothing
      _ -> do
          let libstring = show $ getLibId ln
          unless (isSuffixOf libstring $ rmSuffix file) $ lift
            $ putIfVerbose opts 1
            $ "### file name '" ++ file ++ "' does not match library name '"
            ++ libstring ++ "'"
          lift $ putIfVerbose opts 1 $ "Analyzing "
               ++ (if noLibName then "file " ++ file ++ " as " else "")
               ++ "library " ++ show ln
          (_, ld, _, lenv) <- anaLibDefn lgraph opts topLns libenv initDG ast
          case Map.lookup ln lenv of
              Nothing -> error $ "anaString: missing library: " ++ show ln
              Just dg -> lift $ do
                  writeLibDefn (globalAnnos dg) file opts ld
                  when (hasEnvOut opts)
                        (writeFileInfo opts ln file ld dg)
                  return (ln, lenv)
    Nothing -> liftR $ Result ds Nothing

-- lookup or read a library
anaLibFile :: LogicGraph -> HetcatsOpts -> LNS -> LibEnv -> DGraph -> LibName
           -> ResultT IO (LibName, LibEnv)
anaLibFile lgraph opts topLns libenv initDG ln =
    let lnstr = show ln in case Map.lookup ln libenv of
    Just _ -> do
        analyzing opts $ "from " ++ lnstr
        return (ln, libenv)
    Nothing -> do
            putMessageIORes opts 1 $ "Downloading " ++ lnstr ++ " ..."
            res <- anaLibFileOrGetEnv lgraph
              (if recurse opts then opts else opts { outtypes = [] })
              (Set.insert ln topLns) libenv initDG ln $ libNameToFile ln
            putMessageIORes opts 1 $ "... loaded " ++ lnstr
            return res

-- | lookup or read a library
anaLibFileOrGetEnv :: LogicGraph -> HetcatsOpts -> LNS -> LibEnv -> DGraph
                   -> LibName -> FilePath -> ResultT IO (LibName, LibEnv)
anaLibFileOrGetEnv lgraph opts topLns libenv initDG libname file = ResultT $ do
     let envFile = rmSuffix file ++ envSuffix
     recent_envFile <- checkRecentEnv opts envFile file
     if recent_envFile
        then do
             mgc <- readVerbose lgraph opts libname envFile
             case mgc of
                 Nothing -> runResultT $ do
                     lift $ putIfVerbose opts 1 $ "Deleting " ++ envFile
                     lift $ removeFile envFile
                     anaSourceFile lgraph opts topLns libenv initDG file
                 Just (ld, gc) -> do
                     writeLibDefn (globalAnnos gc) file opts ld
                          -- get all DGRefs from DGraph
                     Result ds mEnv <- runResultT $ foldl
                         ( \ ioLibEnv labOfDG -> let node = snd labOfDG in
                               if isDGRef node then do
                                 let ln = dgn_libname node
                                 p_libEnv <- ioLibEnv
                                 if Map.member ln p_libEnv then
                                    return p_libEnv
                                    else fmap snd $ anaLibFile lgraph
                                         opts topLns p_libEnv initDG ln
                               else ioLibEnv)
                         (return $ Map.insert libname gc libenv)
                         $ labNodesDG gc
                     return $ Result ds $ fmap
                                ( \ rEnv -> (libname, rEnv)) mEnv
        else runResultT $ anaSourceFile lgraph opts topLns libenv initDG file

-- | analyze a LIB_DEFN
-- Parameters: logic graph, default logic, opts, library env, LIB_DEFN
-- call this function as follows:
-- do Result diags res <- runResultT (anaLibDefn ...)
--    mapM_ (putStrLn . show) diags
anaLibDefn :: LogicGraph -> HetcatsOpts -> LNS -> LibEnv -> DGraph -> LIB_DEFN
  -> ResultT IO (LibName, LIB_DEFN, DGraph, LibEnv)
anaLibDefn lgraph opts topLns libenv dg (Lib_defn ln alibItems pos ans) = do
  gannos <- showDiags1 opts $ liftR $ addGlobalAnnos emptyGlobalAnnos ans
  (libItems', dg', libenv', _) <- foldM (anaLibItemAux opts topLns)
      ([], dg { globalAnnos = gannos }, libenv, lgraph) (map item alibItems)
  let dg1 = computeDGraphTheories libenv' $ markHiding libenv' dg'
  return (ln, Lib_defn ln
      (zipWith replaceAnnoted (reverse libItems') alibItems)
      pos ans, dg1, Map.insert ln dg1 libenv')

anaLibItemAux :: HetcatsOpts -> LNS -> ([LIB_ITEM], DGraph, LibEnv, LogicGraph)
  -> LIB_ITEM -> ResultT IO ([LIB_ITEM], DGraph, LibEnv, LogicGraph)
anaLibItemAux opts topLns (libItems', dg1, libenv1, lG) libItem =
    let newLG = case libItems' of
          [] -> lG { currentLogic = defLogic opts }
          Logic_decl (Logic_name logTok _) _ : _ ->
              lG { currentLogic = tokStr logTok }
          _ -> lG
    in ResultT (do
      Result diags2 res <-
         runResultT $ anaLibItem newLG opts topLns libenv1 dg1 libItem
      runResultT $ showDiags1 opts (liftR (Result diags2 res))
      let mRes = case res of
             Just (libItem', dg1', libenv1') ->
                 Just (libItem' : libItems', dg1', libenv1', newLG)
             Nothing -> Nothing
      if outputToStdout opts then
         if hasErrors diags2 then
            fail "Stopped due to errors"
            else runResultT $ liftR $ Result [] mRes
         else runResultT $ liftR $ Result diags2 mRes)

putMessageIORes :: HetcatsOpts -> Int -> String -> ResultT IO ()
putMessageIORes opts i msg =
   if outputToStdout opts
   then lift $ putIfVerbose opts i msg
   else liftR $ message () msg

analyzing :: HetcatsOpts -> String -> ResultT IO ()
analyzing opts = putMessageIORes opts 1 . ("Analyzing " ++)

alreadyDefined :: String -> String
alreadyDefined str = "Name " ++ str ++ " already defined"

-- | analyze a GENERICITY
anaGenericity :: LogicGraph -> DGraph -> HetcatsOpts -> NodeName -> GENERICITY
  -> Result (GENERICITY, GenSig, DGraph)
anaGenericity lg dg opts name
    gen@(Genericity (Params psps) (Imported isps) pos) =
  adjustPos pos $ case psps of
  [] -> do -- no parameter ...
    unless (null isps) $ plain_error ()
      "Parameterless specifications must not have imports" pos
    l <- lookupCurrentLogic "GENERICITY" lg
    return (gen, GenSig (EmptyNode l) [] $ EmptyNode l, dg)
  _ -> do
   l <- lookupCurrentLogic "IMPORTS" lg
   (imps', nsigI, dg') <- case isps of
     [] -> return ([], EmptyNode l, dg)
     _ -> do
      (is', _, nsig', dgI) <- anaUnion False lg dg (EmptyNode l)
          (extName "Imports" name) opts isps
      return (is', JustNode nsig', dgI)
   (ps', nsigPs, ns, dg'') <- anaUnion False lg dg' nsigI
          (extName "Parameters" name) opts psps
   return (Genericity (Params ps') (Imported imps') pos,
     GenSig nsigI nsigPs $ JustNode ns, dg'')

-- | analyse a LIB_ITEM
anaLibItem :: LogicGraph -> HetcatsOpts -> LNS -> LibEnv -> DGraph -> LIB_ITEM
  -> ResultT IO (LIB_ITEM, DGraph, LibEnv)
anaLibItem lgraph opts topLns libenv dg itm = case itm of
  Spec_defn spn gen asp pos -> do
    let spstr = tokStr spn
        nName = makeName spn
    analyzing opts $ "spec " ++ spstr
    (gen', gsig@(GenSig _ _ allparams), dg') <-
      liftR $ anaGenericity lgraph dg opts nName gen
    (sanno1, impliesA) <- liftR $ getSpecAnnos pos asp
    when impliesA $ liftR $ plain_error ()
       "unexpected initial %implies in spec-defn" pos
    (sp', body, dg'') <-
      liftR (anaSpecTop sanno1 True lgraph dg'
             allparams nName opts (item asp))
    let libItem' = Spec_defn spn gen' (replaceAnnoted sp' asp) pos
        genv = globalEnv dg
    if Map.member spn genv
      then liftR $ plain_error (libItem', dg'', libenv)
               (alreadyDefined spstr) pos
      else return
        ( libItem'
        , dg'' { globalEnv = Map.insert spn (SpecEntry
                 $ ExtGenSig gsig body) genv }
        , libenv)
  View_defn vn gen vt gsis pos -> do
    analyzing opts $ "view " ++ tokStr vn
    liftR $ anaViewDefn lgraph libenv dg opts vn gen vt gsis pos
  Arch_spec_defn asn asp pos -> do
    let asstr = tokStr asn
    analyzing opts $ "arch spec " ++ asstr
    (archSig, dg', asp') <- liftR $ anaArchSpec lgraph dg opts $ item asp
    let asd' = Arch_spec_defn asn (replaceAnnoted asp' asp) pos
        genv = globalEnv dg'
    if Map.member asn genv
      then liftR $ plain_error (asd', dg', libenv) (alreadyDefined asstr) pos
      else return (asd', dg'
             { globalEnv = Map.insert asn (ArchEntry archSig) genv },
             libenv)
  Unit_spec_defn usn usp pos -> do
    let usstr = tokStr usn
    analyzing opts $ "unit spec " ++ usstr
    l <- lookupCurrentLogic "Unit_spec_defn" lgraph
    (unitSig, dg', usp') <-
        liftR $ anaUnitSpec lgraph dg opts (EmptyNode l) usp
    let usd' = Unit_spec_defn usn usp' pos
        genv = globalEnv dg'
    if Map.member usn genv
      then liftR $ plain_error (itm, dg', libenv) (alreadyDefined usstr) pos
      else return (usd', dg'
             { globalEnv = Map.insert usn (UnitEntry unitSig) genv },
             libenv)
  Ref_spec_defn rn _ pos -> do
    let rnstr = tokStr rn
    analyzing opts $ "refinement "
      ++ rnstr ++ "\n  (refinement analysis not implemented yet)"
    let genv = globalEnv dg
    if Map.member rn genv
      then liftR $ plain_error (itm, dg, libenv) (alreadyDefined rnstr) pos
      else return ( itm, dg { globalEnv = Map.insert rn RefEntry genv }
                  , libenv)
  Logic_decl (Logic_name logTok _) _ -> do
    logNm <- lookupLogic "LOGIC DECLARATION:" (tokStr logTok) lgraph
    putMessageIORes opts 1 $ "logic " ++ show logNm
    return (itm, dg, libenv)
  Download_items ln items _ -> if Set.member ln topLns then
    liftR $ mkError "illegal cyclic library import"
      $ Set.map getLibId topLns
    else do
        (ln', libenv') <- anaLibFile lgraph opts topLns libenv
          (cpIndexMaps dg emptyDG) ln
        if ln == ln' then case Map.lookup ln libenv' of
          Nothing -> error $ "Internal error: did not find library "
            ++ show ln ++ " available: " ++ show (Map.keys libenv')
          Just dg' -> do
            let dg0 = cpIndexMaps dg' dg
            dg1 <- liftR $ anaItemNamesOrMaps libenv' ln dg' dg0 items
            return (itm, dg1, libenv')
          else liftR $ mkError ("downloaded library '" ++ show ln'
            ++ "' does not match library name") $ getLibId ln

-- the first DGraph dg' is that of the imported library
anaItemNamesOrMaps :: LibEnv -> LibName -> DGraph -> DGraph
  -> [ITEM_NAME_OR_MAP] -> Result DGraph
anaItemNamesOrMaps libenv' ln dg' dg items = do
  (genv1, dg1) <- foldM
    (anaItemNameOrMap libenv' ln $ globalEnv dg') (globalEnv dg, dg) items
  gannos'' <- globalAnnos dg `mergeGlobalAnnos` globalAnnos dg'
  return dg1
    { globalAnnos = gannos''
    , globalEnv = genv1 }

-- | analyse genericity and view type and construct gmorphism
anaViewDefn :: LogicGraph -> LibEnv -> DGraph -> HetcatsOpts -> SIMPLE_ID
  -> GENERICITY -> VIEW_TYPE -> [G_mapping] -> Range
  -> Result (LIB_ITEM, DGraph, LibEnv)
anaViewDefn lgraph libenv dg opts vn gen vt gsis pos = do
  let vName = makeName vn
  (gen', gsig@(GenSig _ _ allparams), dg') <-
       anaGenericity lgraph dg opts vName gen
  (vt', (src@(NodeSig nodeS gsigmaS)
        , tar@(NodeSig nodeT gsigmaT@(G_sign lidT _ _))), dg'') <-
       anaViewType lgraph dg' allparams opts vName vt
  let genv = globalEnv dg''
  if Map.member vn genv
    then plain_error (View_defn vn gen' vt' gsis pos, dg'', libenv)
                    (alreadyDefined $ tokStr vn) pos
    else do
      (gsigmaS', imor) <- gSigCoerce lgraph gsigmaS (Logic lidT)
      tmor <- gEmbedComorphism imor gsigmaS
      emor <- fmap gEmbed $ anaGmaps lgraph opts pos gsigmaS' gsigmaT gsis
      gmor <- comp tmor emor
      let vsig = ExtViewSig src gmor $ ExtGenSig gsig tar
      return (View_defn vn gen' vt' gsis pos,
                (insLink dg'' gmor globalThm
                 (DGLinkView vn) nodeS nodeT)
                -- 'LeftOpen' for conserv correct?
                { globalEnv = Map.insert vn (ViewEntry vsig) genv }
               , libenv)

-- | analyze a VIEW_TYPE
-- The first three arguments give the global context
-- The AnyLogic is the current logic
-- The NodeSig is the signature of the parameter of the view
-- flag, whether just the structure shall be analysed
anaViewType :: LogicGraph -> DGraph -> MaybeNode -> HetcatsOpts -> NodeName
  -> VIEW_TYPE -> Result (VIEW_TYPE, (NodeSig, NodeSig), DGraph)
anaViewType lg dg parSig opts name (View_type aspSrc aspTar pos) = do
  l <- lookupCurrentLogic "VIEW_TYPE" lg
  (spSrc', srcNsig, dg') <- adjustPos pos $ anaSpec False lg dg (EmptyNode l)
    (extName "Source" name) opts (item aspSrc)
  (spTar', tarNsig, dg'') <- adjustPos pos $ anaSpec True lg dg' parSig
    (extName "Target" name) opts (item aspTar)
  return (View_type (replaceAnnoted spSrc' aspSrc)
                    (replaceAnnoted spTar' aspTar)
                    pos,
          (srcNsig, tarNsig), dg'')

anaItemNameOrMap :: LibEnv -> LibName -> GlobalEnv -> (GlobalEnv, DGraph)
  -> ITEM_NAME_OR_MAP -> Result (GlobalEnv, DGraph)
anaItemNameOrMap libenv ln genv' res itm =
   anaItemNameOrMap1 libenv ln genv' res $ case itm of
     Item_name name -> (name, name)
     Item_name_map old new _ -> (old, new)

-- | Auxiliary function for not yet implemented features
anaErr :: String -> a
anaErr f = error $ "*** Analysis of " ++ f ++ " is not yet implemented!"

anaItemNameOrMap1 :: LibEnv -> LibName -> GlobalEnv -> (GlobalEnv, DGraph)
  -> (SIMPLE_ID, SIMPLE_ID) -> Result (GlobalEnv, DGraph)
anaItemNameOrMap1 libenv ln genv' (genv, dg) (old, new) = do
  let newName = makeName new
  entry <- maybeToResult (tokPos old)
            (tokStr old ++ " not found") (Map.lookup old genv')
  case Map.lookup new genv of
    Nothing -> return ()
    Just _ -> fail (tokStr new ++ " already used")
  case entry of
    SpecEntry extsig ->
      let (dg1, extsig1) = refExtsig libenv ln dg newName extsig
          genv1 = Map.insert new (SpecEntry extsig1) genv
       in return (genv1,dg1)
    ViewEntry vsig ->
      let (dg1,vsig1) = refViewsig libenv ln dg newName vsig
          genv1 = Map.insert new (ViewEntry vsig1) genv
      in return (genv1,dg1)
    ArchEntry _asig -> anaErr "arch spec download"
    UnitEntry _usig -> anaErr "unit spec download"
    RefEntry -> anaErr "ref spec download"

refNodesig :: LibEnv -> LibName -> DGraph -> (NodeName, NodeSig)
           -> (DGraph, NodeSig)
refNodesig libenv refln dg (name, NodeSig refn sigma@(G_sign lid sig ind)) =
  let (ln, (n, lbl)) = getActualParent libenv refln refn
      refInfo = newRefInfo ln n
      new = newInfoNodeLab name refInfo
        $ noSensGTheory lid sig ind
      nodeCont = new { globalTheory = globalTheory lbl }
      node = getNewNodeDG dg
   in case lookupInAllRefNodesDG refInfo dg of
        Just existNode -> (dg, NodeSig existNode sigma)
        Nothing ->
          ( addToRefNodesDG node refInfo $ insNodeDG (node, nodeCont) dg
          , NodeSig node sigma)

{- | get to the actual parent which is not a referenced node, so that
     the small chains between nodes in different library can be advoided.
     (details see ticket 5)
-}
getActualParent :: LibEnv -> LibName -> Node -> (LibName, LNode DGNodeLab)
getActualParent libenv ln n =
   let refLab = labDG (lookupDGraph ln libenv) n in
   if isDGRef refLab then
        -- recursively goes to parent of the current node, but
        -- it actually would only be done once
        getActualParent libenv (dgn_libname refLab) (dgn_node refLab)
   else (ln, (n, refLab))

refNodesigs :: LibEnv -> LibName -> DGraph -> [(NodeName, NodeSig)]
            -> (DGraph, [NodeSig])
refNodesigs libenv = mapAccumR . refNodesig libenv

refExtsig :: LibEnv -> LibName -> DGraph -> NodeName -> ExtGenSig
          -> (DGraph, ExtGenSig)
refExtsig libenv ln dg name (ExtGenSig (GenSig imps params gsigmaP) body) = let
  pName = extName "Parameters" name
  (dg1, imps1) = case imps of
    EmptyNode _ -> (dg, imps)
    JustNode ns -> let
        (dg0, nns) = refNodesig libenv ln dg (extName "Imports" name, ns)
        in (dg0, JustNode nns)
  (dg2, params1) = refNodesigs libenv ln dg1
      $ snd $ foldr (\ p (n, l) -> let nn = inc n in
              (nn, (nn, p) : l)) (pName, []) params
  (dg3, gsigmaP1) = case gsigmaP of
    EmptyNode _ -> (dg, gsigmaP)
    JustNode ns -> let
        (dg0, nns) = refNodesig libenv ln dg2 (pName, ns)
        in (dg0, JustNode nns)
  (dg4, body1) = refNodesig libenv ln dg3 (name, body)
  in (dg4, ExtGenSig (GenSig imps1 params1 gsigmaP1) body1)

refViewsig :: LibEnv -> LibName -> DGraph -> NodeName -> ExtViewSig
           -> (DGraph, ExtViewSig)
refViewsig libenv ln dg name (ExtViewSig src mor extsig) = let
  (dg1, src1) = refNodesig libenv ln dg (extName "Source" name, src)
  (dg2, extsig1) = refExtsig libenv ln dg1 (extName "Target" name) extsig
  in (dg2, ExtViewSig src1 mor extsig1)
