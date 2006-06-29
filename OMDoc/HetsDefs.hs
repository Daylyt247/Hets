{- |
Module      :  $Header$
Copyright   :  (c) Hendrik Iben, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hiben@tzi.de
Stability   :  provisional
Portability :  non-portable(Logic)

  Additional definitions for interfacing Hets
-}
module OMDoc.HetsDefs
  (
      module Driver.Options
    , module OMDoc.HetsDefs
    , module Syntax.AS_Library
  )
  where

import Data.Graph.Inductive.Graph
import qualified Data.Graph.Inductive.Graph as Graph 

import Common.AS_Annotation
import Common.GlobalAnnotations (emptyGlobalAnnos)

import Syntax.AS_Library --(LIB_NAME(),LIB_DEFN()) 

import Driver.Options

import Logic.Grothendieck hiding (Morphism)

import Static.DevGraph

import CASL.AS_Basic_CASL
import CASL.Logic_CASL

import CASL.Sign
import CASL.Morphism
import qualified CASL.AS_Basic_CASL as CASLBasic
import Data.Typeable
import qualified Common.Id as Id
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Rel as Rel
import qualified Logic.Grothendieck as Gro
import qualified Common.AS_Annotation as Ann
import qualified Data.Maybe as Data.Maybe

import qualified Logic.Prover as Prover

import qualified Common.OrderedMap as OMap

import qualified Debug.Trace as Debug.Trace

import qualified Data.List as Data.List

import Char (isSpace)
import Data.Maybe (fromMaybe)

import OMDoc.Util 

-- | shortcut to Debug.Trace.trace
dtt::String->a->a
dtt = Debug.Trace.trace

-- | "alias" for defaultHetcatsOpts (for export)
dho::HetcatsOpts
dho = defaultHetcatsOpts

-- | transform a list of named sentences to a list with name-sentence-tuples
transSen::[Ann.Named CASLFORMULA]->[(String, CASLFORMULA)]
transSen [] = []
transSen ((Ann.NamedSen n _ _ s):rest) = [(n, s)] ++ transSen rest

-- | transform a list of name-sentence-tuples to a list of named sentences
transSenBack::[(String, CASLFORMULA)]->[Ann.Named CASLFORMULA]
transSenBack [] = []
transSenBack ((n, s):rest) = (Ann.NamedSen n False False s):(transSenBack rest)

-- | strip names from a list of name-formula-tuples
getPureFormulas::[(String, CASLFORMULA)]->[CASLFORMULA]
getPureFormulas [] = []
getPureFormulas ((_, f):rest) = [f] ++ getPureFormulas rest

-- Cast Signature to CASLSignature if possible
getCASLSign::G_sign->(Maybe CASLSign)
getCASLSign (G_sign _ sign) = cast sign -- sign is of class Typeable -> cast -> (Typeable a, Typeable b)->(Maybe b)

getJustCASLSign::(Maybe CASLSign)->CASLSign
getJustCASLSign (Just cs) = cs
getJustCASLSign Nothing = error "Nothing"

-- Get a String-representation of a Set
getSetStringList::(Show a)=>Set.Set a -> [String]
getSetStringList s = map show $ Set.toList s

-- " of a Map
getMapStringsList::(Show a, Show b)=>Map.Map a b -> [(String, String)]
getMapStringsList s = map (\(a, b) -> (show a, show b)) $ Map.toList s

-- " of a Relation
getRelStringsList::(Show a)=>Rel.Rel a -> [(String, String)]
getRelStringsList s = map (\(a, b) -> (show a, show b)) $ Rel.toList s

-- Get strings to represent an operator-mapping
getOpMapStringsList::OpMap->[(String, [(String, [String], String)])]
getOpMapStringsList om = map (\(a, b) -> ((show a), map opTypeToStrings (Set.toList b))) (Map.toList om) where
  opTypeToStrings::OpType->(String, [String], String)
  opTypeToStrings (OpType {opKind=ok, opArgs=oa, opRes=or' }) = (show ok, map show oa, show or' )
  
-- Get strings to represent a predicate-mapping
getPredTypeStringsList::(Map.Map (Id.Id) (Set.Set PredType))->[(String, [[String]])]
getPredTypeStringsList pm = map (\(id' , pts) -> (show id' ,
          map (\(PredType set) -> map show set) $ Set.toList pts ) ) $ Map.toList pm

-- String representation of non ignored CASLSign-Components         
data CASLSignStrings = CASLSignStrings {
       sortSetStrings :: [String]
      ,sortRelStrings :: [(String, String)]
      ,opMapStrings :: [(String, [(String, [String], String)])]
      ,predMapStrings :: [(String, [[String]])]
      } deriving Show

-- Conversion from Sign to Stringrepresentation
caslSignToStrings::CASLSign->CASLSignStrings
caslSignToStrings cs =
  CASLSignStrings {  sortSetStrings=( getSetStringList $ sortSet cs )
        ,sortRelStrings=( getRelStringsList $ sortRel cs)
        ,opMapStrings = ( getOpMapStringsList $ opMap cs)
        ,predMapStrings = ( getPredTypeStringsList $ predMap cs )
       }

-- Create a simple id from a string
stringToSimpleId::String->Id.SIMPLE_ID
stringToSimpleId = Id.mkSimpleId
       
-- Fast Id construction from a String
stringToId::String->Id.Id
stringToId = Id.simpleIdToId . Id.mkSimpleId

-- SORT is Id so hopefully this simple mapping does it...
sortSetStringsToSortSet::[String]->(Set.Set Id.Id)
sortSetStringsToSortSet sorts = Set.fromList $ map stringToId sorts

-- Same for Relations
sortRelStringsToSortRel::[(String, String)]->(Rel.Rel Id.Id)
sortRelStringsToSortRel l = Rel.fromList $ map (\(a, b) -> ((stringToId a), (stringToId b))) l

{-
This might be a source of later errors.
FunKinds are checked against a String... needs more work.
-}
opMapStringsToOpMap::[(String, [(String, [String], String)])]->OpMap
opMapStringsToOpMap ops = foldr (\(id' , ops' ) m -> Map.insert (stringToId id' ) (Set.fromList $ map mkOpType ops' ) m) Map.empty ops where  
  mkOpType::(String,[String],String)->OpType
  mkOpType (opkind, args, res) = OpType
          (if opkind == "Partial" then CASLBasic.Partial else CASLBasic.Total)
          (map stringToId args)
          (stringToId res)

{-
Predicate-mapping
-}
predMapStringsToPredMap::[(String, [[String]])]->(Map.Map Id.Id (Set.Set PredType))
predMapStringsToPredMap pres = foldr (\(id' , args) m -> Map.insert
              (stringToId id' )
              (Set.fromList $ map (\n -> PredType (map (\s -> stringToId s) n)) args)
              m
            ) Map.empty pres

-- Conversion from String-Form to Sign
stringsToCASLSign::CASLSignStrings->CASLSign
stringsToCASLSign cs =
  Sign {
     sortSet = sortSetStringsToSortSet $ sortSetStrings cs
    ,sortRel = sortRelStringsToSortRel $ sortRelStrings cs
    ,opMap = opMapStringsToOpMap $ opMapStrings cs
    ,assocOps = Map.empty -- ignored
    ,predMap = predMapStringsToPredMap $ predMapStrings cs
    ,varMap = Map.empty -- ignored
    ,sentences = [] -- ignored
    ,envDiags = [] -- ignored
    ,globAnnos = emptyGlobalAnnos
    ,extendedInfo = () -- ignored
  }


-- Filter out links for collecting sorts, rels, preds...
-- only four types of links are allowed (and afaik needed for this)
linkFilter::[(Graph.LEdge DGLinkLab)]->[(Graph.LEdge DGLinkLab)]
linkFilter [] = []
linkFilter ((l@(_,_,link)):rest) =
  (case dgl_type link of
    LocalDef -> [l]
    GlobalDef -> [l]
    HidingDef -> [l]
    (FreeDef {}) -> [l]
    (CofreeDef {}) -> [l]
    -- LocalThm's with 'Mono' cons tend to link back to their 
    -- origin, effectively wiping out the sorts, etc...
    (LocalThm _ c _) -> case c of Def -> [l]; _ -> []
    (GlobalThm _ c _) -> case c of Def -> [l]; _ -> []
    _ -> []) ++ linkFilter rest
    
-- return a list with all NodeLabs where imports a made (see also 'linkFilter')
inputNodeLabs::DGraph->Graph.Node->[DGNodeLab]
inputNodeLabs dg n = map (\(Just a) -> a) $ map (\(m,_,_) -> Graph.lab dg m) $ linkFilter $ Graph.inn dg n

inputLNodes::DGraph->Graph.Node->[Graph.LNode DGNodeLab]
inputLNodes dg n = map (\(m,_,_) -> (m, (\(Just a) -> a) $ Graph.lab dg m) ) $ linkFilter $ Graph.inn dg n

inputNodes::DGraph->Graph.Node->[Graph.Node]
inputNodes dg n = map (\(m,_,_) -> m) $ linkFilter $ Graph.inn dg n

innNodes::DGraph->Graph.Node->[Graph.LNode DGNodeLab]
innNodes dg n =
  map
    (\(m,_,_) ->
      (m, fromMaybe (error "corrupt graph!") (Graph.lab dg m))
    )
    (Graph.inn dg n)

getCASLMorphLL::DGLinkLab->(CASL.Morphism.Morphism () () ())
getCASLMorphLL edge =
  fromMaybe (error "cannot cast morphism to CASL.Morphism")  $ (\(Logic.Grothendieck.GMorphism _ _ morph) -> Data.Typeable.cast morph :: (Maybe (CASL.Morphism.Morphism () () ()))) $ dgl_morphism edge

getCASLMorph::(Graph.LEdge DGLinkLab)->(CASL.Morphism.Morphism () () ())
getCASLMorph (_,_,edge) = getCASLMorphLL edge

getMCASLMorph::(Graph.LEdge DGLinkLab)->(Maybe (CASL.Morphism.Morphism () () ()))
getMCASLMorph (_,_,edge) = (\(Logic.Grothendieck.GMorphism _ _ morph) -> Data.Typeable.cast morph :: (Maybe (CASL.Morphism.Morphism () () ()))) $ dgl_morphism edge

signViaMorphism::DGraph->Graph.Node->CASLSign
signViaMorphism dg n =
  let outedges = Graph.out dg n
  in  if outedges == [] then
        emptySign ()
      else
        let
          mcaslmorph = getMCASLMorph $ head outedges
        in  case mcaslmorph of
            (Just caslmorph) -> CASL.Morphism.msource caslmorph
            _ -> emptySign ()
            
data WithOrigin a b = WithOrigin { woItem::a, woOrigin::b }
    
--data WithOriginNode a = WithOriginNode { wonItem::a, wonOrigin::Graph.Node }
type WithOriginNode a = WithOrigin a Graph.Node


-- Equality and Ordering may not only depend on the stored items as this would
-- lead to removal in sets,maps,etc...
-- But still equality-checks on items are needed.

equalItems::(Eq a)=>WithOrigin a b->WithOrigin a c->Bool
equalItems p q = (woItem p) == (woItem q) 

compareItems::(Ord a)=>WithOrigin a b->WithOrigin a c->Ordering
compareItems p q = compare (woItem p) (woItem q)

instance (Eq a, Eq b)=>Eq (WithOrigin a b) where
  wo1 == wo2 = ((woOrigin wo1) == (woOrigin wo2)) && ((woItem wo1) == (woItem wo2))  
  
instance (Eq a, Ord b, Ord a)=>Ord (WithOrigin a b) where
  compare wo1 wo2 =
    let
      icmp = compare (woItem wo1) (woItem wo2)
    in
      if icmp == EQ then compare (woOrigin wo1) (woOrigin wo2) else icmp 
  
instance (Show a, Show b)=>Show (WithOrigin a b) where
  show wo = (show (woItem wo)) ++ " Origin:(" ++ (show (woOrigin wo)) ++ ")"
  
wonItem::WithOriginNode a->a
wonItem = woItem

wonOrigin::WithOriginNode a->Graph.Node
wonOrigin = woOrigin
  
mkWON::a->Graph.Node->WithOriginNode a
mkWON = WithOrigin
  
originOrder::(Ord o)=>WithOrigin a o->WithOrigin b o->Ordering
originOrder wo1 wo2 = compare (woOrigin wo1) (woOrigin wo2)
  
sameOrigin::(Eq o)=>WithOrigin a o->WithOrigin a o->Bool
sameOrigin wo1 wo2 = (woOrigin wo1) == (woOrigin wo2) 

-- gets something from a DGNode or returns default value for DGRefS
getFromDGNode::DGNodeLab->(DGNodeLab->a)->a->a
getFromDGNode node get' def =
  if isDGRef node then def else
    get' node
    
getFromNode::DGraph->Graph.Node->(DGNodeLab->Bool)->(DGNodeLab->a)->(DGraph->Graph.Node->a)->a
getFromNode dg n usenode getnode getgraphnode =
  let node = (\(Just a) -> a) $ Graph.lab dg n
  in  if usenode node then
      getnode node
    else
      getgraphnode dg n
      
-- generic function to calculate a delta between a node and the nodes it
-- imports from
getFromNodeDelta::DGraph->Graph.Node->(DGNodeLab->a)->(a->a->a)->a->a
getFromNodeDelta dg n get' delta def =
  let
    node = (\(Just a) -> a) $ Graph.lab dg n
    innodes = inputNodeLabs dg n
  in
    foldl (\r n' ->
      delta r $ getFromDGNode n' get' def
      ) (getFromDGNode node get' def) innodes
      
getFromNodeDeltaM::DGraph->Graph.Node->(DGNodeLab->Bool)->(DGNodeLab->a)->(DGraph->Graph.Node->a)->(a->a->a)->a
getFromNodeDeltaM dg n usenode getnode getgraphnode delta =
  let --node = (\(Just a) -> a) $ Graph.lab dg n
    innodes = inputNodes dg n
  in
    foldl (\r n' ->
      let 
        newvalue = getFromNode dg n' usenode getnode getgraphnode
        result = delta r newvalue
      in
        result
      ) (getFromNode dg n usenode getnode getgraphnode) innodes
      
getFromNodeWithOriginsM::
  (Eq b, Show b)=>
  DGraph->
  Graph.Node->
  (DGNodeLab->Bool)->
  (DGNodeLab->a)->
  (DGraph->Graph.Node->a)->
  (a->[b])->
  (b->DGraph->Graph.Node->Bool)->
  (Graph.LEdge DGLinkLab->b->b)->
  ([WithOriginNode b]->c)->
  c
getFromNodeWithOriginsM dg n usenode getnode getgraphnode getcomponents isorigin morph createresult =
  let
    item' = getFromNode dg n usenode getnode getgraphnode
    components = getcomponents item'
    traced = foldl (\traced' c ->
      let
        mo = traceMorphingOrigin dg n c [] isorigin morph
      in
        traced' ++ [case mo of
          Nothing -> mkWON c n -- current node is origin
          (Just o) -> mkWON c o]
        ) [] components
  in
    createresult traced
    
getFromNodeWithOriginsMSet::
  (Eq a, Show a, Ord a)=>
  DGraph->
  Graph.Node->
  (DGNodeLab->Bool)->
  (DGNodeLab->Set.Set a)->
  (DGraph->Graph.Node->Set.Set a)->
  (a->DGraph->Graph.Node->Bool)->
  (Graph.LEdge DGLinkLab->a->a)->
  Set.Set (WithOriginNode a)
getFromNodeWithOriginsMSet dg n usenode getset getgraphset isorigin morph =
  getFromNodeWithOriginsM dg n usenode getset getgraphset Set.toList isorigin morph Set.fromList

getFromCASLSignWithOrigins::
  (Eq b, Show b)=>
  DGraph->Graph.Node->(CASLSign->a)->(a->[b])->(b->a->Bool)
  ->(Graph.LEdge DGLinkLab->b->b)
  ->([WithOriginNode b]->c)
  ->c
getFromCASLSignWithOrigins dg n caslget getcomponents isorigin morph createresult =
  getFromNodeWithOriginsM dg n (\_ -> False) (\_ -> undefined::a)
    (\dg' n' -> getFromCASLSignM dg' n' caslget)
    getcomponents
    (\i dg' n' -> isorigin i (getFromCASLSignM dg' n' caslget))
    morph
    createresult
    
getSortsFromNodeWithOrigins::
  DGraph->Graph.Node->SortsWO
getSortsFromNodeWithOrigins dg n =
  getFromCASLSignWithOrigins
    dg
    n
    sortSet
    Set.toList
    Set.member
    idMorph
    Set.fromList
    
getOpsMapFromNodeWithOrigins::
  DGraph->Graph.Node->OpsWO
getOpsMapFromNodeWithOrigins dg n =
  getFromCASLSignWithOrigins
    dg
    n
    opMap
    Map.toList
    (\(mid, mtype) om -> case Map.lookup mid om of
      Nothing -> False
      (Just (mtype')) -> mtype == mtype')
    idMorph
    (Map.fromList . (map (\mewo ->
      (mkWON (fst (wonItem mewo)) (wonOrigin mewo), snd (wonItem mewo)))))
      
getAssocOpsMapFromNodeWithOrigins::
  DGraph->Graph.Node->OpsWO
getAssocOpsMapFromNodeWithOrigins dg n =
  getFromCASLSignWithOrigins
    dg
    n
    assocOps
    Map.toList
    (\(mid, mtype) om -> case Map.lookup mid om of
      Nothing -> False
      (Just (mtype')) -> mtype == mtype')
    idMorph
    (Map.fromList . (map (\mewo ->
      (mkWON (fst (wonItem mewo)) (wonOrigin mewo), snd (wonItem mewo)))))
      
getPredsMapFromNodeWithOrigins::
  DGraph->Graph.Node->PredsWO
getPredsMapFromNodeWithOrigins dg n =
  getFromCASLSignWithOrigins
    dg
    n
    predMap
    Map.toList
    (\(mid, mtype) om -> case Map.lookup mid om of
      Nothing -> False
      (Just (mtype')) -> mtype == mtype')
    idMorph
    (Map.fromList . (map (\mewo ->
      (mkWON (fst (wonItem mewo)) (wonOrigin mewo), snd (wonItem mewo)))))
      
getSensFromNodeWithOrigins::
  DGraph->Graph.Node->SensWO
getSensFromNodeWithOrigins dg n =
  getFromNodeWithOriginsMSet
    dg
    n
    (\_ -> True)
    (Set.fromList . getNodeSentences)
    (\_ _ -> undefined::Set.Set (Ann.Named CASLFORMULA))
    (\s dg' n' ->
      case lab dg' n' of
        Nothing -> False
        (Just node) -> elem s (getNodeSentences node)
    )
    idMorph --sentences don't morph
      
traceOrigin::DGraph->Graph.Node->[Graph.Node]->(DGraph->Graph.Node->Bool)->Maybe Graph.Node
traceOrigin dg n visited test =
  if (elem n visited) -- circle encountered...
    then
      Nothing -- we are performing a depth-search so terminate this tree
    else
      -- check if this node still carries the attribute
      if not $ test dg n
        then
          -- it does not, but the previous node did
          if (length visited) == 0
            then
              {-  there was no previous node. this means the start
                node did not have the attribute searched for -}
              Debug.Trace.trace
                "traceOrigin: search from invalid node"
                Nothing
            else
              -- normal case, head is the previous node
              (Just (head visited))
        else
          -- this node still carries the attribute
          let
            -- get possible node for import (OMDDoc-specific)
            innodes = inputNodes dg n
            -- find first higher origin
            mo = first
                (\n' -> traceOrigin dg n' (n:visited) test)
                innodes
          in
            -- if there is no higher origin, this node is the origin
            case mo of
              Nothing ->
                {-  if further search fails, then this
                  node must be the origin -}
                (Just n) 
              (Just _) ->
                -- else use found origin
                mo

-- this works, but still renaming must be handled special...
traceMorphingOrigin::
  (Eq a, Show a)=>
  DGraph
  ->Graph.Node
  ->a
  ->[Graph.Node]
  ->(a->DGraph->Graph.Node->Bool)
  ->(Graph.LEdge DGLinkLab->a->a)
  ->Maybe Graph.Node
traceMorphingOrigin
  dg
  n
  a
  visited
  atest
  amorph =
  if (elem n visited) -- circle encountered...
    then
      Nothing -- we are performing a depth-search so terminate this tree
    else
      -- check if this node still carries the attribute
      if not $ atest a dg n
        then
          -- it does not, but the previous node did
          if (length visited) == 0
            then
              {-  there was no previous node. this means the start
                node did not have the attribute searched for -}
              Debug.Trace.trace
                "traceMorphismOrigin: search from invalid node"
                Nothing
            else
              -- normal case, head is the previous node
              (Just (head visited))
        else
          -- this node still carries the attribute
          let
            -- get possible node for import (OMDDoc-specific)
            -- find first higher origin
            mo = first
                (\edge@(from, _, e) ->
                  let
                    ma = amorph edge a
                  in
                    (
                    if (ma /= a)
                      then
                        Debug.Trace.trace ("Going Deeper, change from " ++ show a ++ " to " ++ show ma)
                      else
                        id
                    ) $
                    traceMorphingOrigin dg from ma (n:visited) atest amorph
                )
                (Graph.inn dg n)
          in
            -- if there is no higher origin, this node is the origin
            case mo of
              Nothing ->
                {-  if further search fails, then this
                  node must be the origin -}
                (Just n) 
              (Just _) ->
                -- else use found origin
                mo

-- embed old checks...
nullMorphCheck::forall a . (DGraph->Graph.Node->Bool)->(DGraph->Graph.Node->a->Bool)
nullMorphCheck check = (\dg n _ -> check dg n)

idMorph::forall a . Graph.LEdge DGLinkLab->a->a
idMorph _ a = a

morphByMorphism::forall a . (Morphism () () ()->a->a)->(Graph.LEdge DGLinkLab->a->a)
morphByMorphism morph =
  (\edge@(_, _, dgl) a ->
    let
      caslmorph = getCASLMorphLL dgl
    in
      morph caslmorph a
  )

sortMorph::Graph.LEdge DGLinkLab->SORT->SORT
sortMorph = morphByMorphism sortBeforeMorphism
    

-- helper function to extract an element from the caslsign of a node
-- or to provide a safe default
getFromCASLSign::DGNodeLab->(CASLSign->a)->a->a
getFromCASLSign node get' def =
  getFromDGNode
    node
    (\n ->
      let caslsign = getJustCASLSign $ getCASLSign (dgn_sign n)
      in get' caslsign
    )
    def
    
getFromCASLSignM::DGraph->Graph.Node->(CASLSign->a)->a
getFromCASLSignM dg n get' =
  let
    node = (\(Just a) -> a) $ Graph.lab dg n
    caslsign = if isDGRef node
          --then signViaMorphism dg n
          then getJustCASLSign $ getCASLSign (dgn_sign node)
          else getJustCASLSign $ getCASLSign (dgn_sign node)
  in  get' caslsign
      
-- wrapper around 'getFromNodeDelta' for CASLSign-specific operations
getFromCASLSignDelta::DGraph->Graph.Node->(CASLSign->a)->(a->a->a)->a->a
getFromCASLSignDelta dg n get' delta def =
  getFromNodeDelta dg n (\g -> getFromCASLSign g get' def) delta def

getFromCASLSignDeltaM::DGraph->Graph.Node->(CASLSign->a)->(a->a->a)->a->a
getFromCASLSignDeltaM dg n get' delta _ =
  getFromNodeDeltaM dg n
    (\_ -> False)
    (\_ -> undefined::a)
    (\dg' n' -> getFromCASLSignM dg' n' get' )
    delta
    
-- extract all sorts from a node that are not imported from other nodes
getNodeDeltaSorts::DGraph->Graph.Node->(Set.Set SORT)
getNodeDeltaSorts dg n = getFromCASLSignDeltaM dg n sortSet Set.difference Set.empty

getRelsFromNodeWithOrigins::Maybe SortsWO->DGraph->Graph.Node->Rel.Rel SORTWO
getRelsFromNodeWithOrigins mswo dg n =
  let
    sortswo = case mswo of
      Nothing -> getSortsFromNodeWithOrigins dg n
      (Just swo) -> swo
    rel = getFromCASLSignM dg n sortRel
  in
    Rel.fromList $
      map (\(a, b) ->
        let
          swoa = case Set.toList $ Set.filter (\m -> a == wonItem m) sortswo of
            [] ->
              Debug.Trace.trace
                ("Unknown Sort in Relation... ("
                  ++ (show a) ++ ")")
                (mkWON a n)
            (i:_) -> i
          swob = case Set.toList $ Set.filter (\m -> b == wonItem m) sortswo of
            [] ->
              Debug.Trace.trace
                ("Unknown Sort in Relation... ("
                  ++ (show b) ++ ")")
                (mkWON b n)
            (i:_) -> i
        in
          (swoa, swob)
          ) $ Rel.toList rel

-- extract all relations from a node that are not imported from other nodes
getNodeDeltaRelations::DGraph->Graph.Node->(Rel.Rel SORT)
getNodeDeltaRelations dg n = getFromCASLSignDeltaM dg n sortRel Rel.difference Rel.empty

-- extract all predicates from a node that are not imported from other nodes
getNodeDeltaPredMaps::DGraph->Graph.Node->(Map.Map Id.Id (Set.Set PredType))    
getNodeDeltaPredMaps dg n = getFromCASLSignDeltaM dg n predMap
  (Map.differenceWith (\a b -> let diff = Set.difference a b in if Set.null diff then Nothing else Just diff))
  Map.empty
  
-- extract all operands from a node that are not imported from other nodes
getNodeDeltaOpMaps::DGraph->Graph.Node->(Map.Map Id.Id (Set.Set OpType))
getNodeDeltaOpMaps dg n = getFromCASLSignDeltaM dg n opMap
  (Map.differenceWith (\a b -> let diff = Set.difference a b in if Set.null diff then Nothing else Just diff))
  Map.empty
  
getSentencesFromG_theory::G_theory->[Ann.Named CASLFORMULA]
getSentencesFromG_theory (G_theory _ _ thsens) =
  let
    (Just csen) = ((cast thsens)::(Maybe (Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof))))
  in Prover.toNamedList csen

-- get CASL-formulas from a node
getNodeSentences::DGNodeLab->[Ann.Named CASLFORMULA]
getNodeSentences (DGRef {}) = []
getNodeSentences node =
  let
    (Just csen) = (\(G_theory _ _ thsens) -> (cast thsens)::(Maybe (Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof)))) $ dgn_theory node
  in Prover.toNamedList csen

-- extract the sentences from a node that are not imported from other nodes       
getNodeDeltaSentences::DGraph->Graph.Node->(Set.Set (Ann.Named CASLFORMULA))
getNodeDeltaSentences dg n = getFromNodeDeltaM dg n (not . isDGRef) (Set.fromList . getNodeSentences) (\_ _ -> Set.empty) Set.difference

-- generic function to perform mapping of node-names to a specific mapping function
getNodeNameMapping::DGraph->(DGraph->Graph.Node->a)->(a->Bool)->(Map.Map String a)
getNodeNameMapping dg mapper dispose =
   foldl (\mapping (n,node) ->
    let mapped = mapper dg n
    in
    if dispose mapped then
      mapping
    else
      -- had to change '#' to '_' because '#' is not valid in names...
      Map.insert (adjustNodeName ("AnonNode_"++(show n)) $ getDGNodeName node) (mapper dg n) mapping
    ) Map.empty $ Graph.labNodes dg

getNodeDGNameMapping::DGraph->(DGraph->Graph.Node->a)->(a->Bool)->(Map.Map NODE_NAME a)
getNodeDGNameMapping dg mapper dispose =
   foldl (\mapping (n,node) ->
    let mapped = mapper dg n
    in
    if dispose mapped then
      mapping
    else
      Map.insert (dgn_name node) mapped mapping
    ) Map.empty $ Graph.labNodes dg
    
getNodeDGNameMappingWO::DGraph->(DGraph->Graph.Node->a)->(a->Bool)->(Map.Map NODE_NAMEWO a)
getNodeDGNameMappingWO dg mapper dispose =
   foldl (\mapping (n,node) ->
    let mapped = mapper dg n
    in
    if dispose mapped then
      mapping
    else
      Map.insert (mkWON (dgn_name node) n) mapped mapping
    ) Map.empty $ Graph.labNodes dg
    
getNodeDGNameMappingWONP::DGraph->(NODE_NAMEWO->DGraph->Graph.Node->a)->(a->Bool)->(Map.Map NODE_NAMEWO a)
getNodeDGNameMappingWONP dg mapper dispose =
   foldl (\mapping (n,node) ->
    let
      thisname = mkWON (dgn_name node) n
      mapped = mapper thisname dg n
    in
    if dispose mapped then
      mapping
    else
      Map.insert thisname mapped mapping
    ) Map.empty $ Graph.labNodes dg
    
type Imports = Set.Set (String, (Maybe MorphismMap), HidingAndRequationList, Bool)
type Sorts = Set.Set SORT
type Rels = Rel.Rel SORT
type Preds = Map.Map Id.Id (Set.Set PredType)
type Ops = Map.Map Id.Id (Set.Set OpType)
type Sens = Set.Set (Ann.Named CASLFORMULA)

type NODE_NAMEWO = WithOriginNode NODE_NAME
type SORTWO = WithOriginNode SORT
type IdWO = WithOriginNode Id.Id
type SentenceWO = WithOriginNode (Ann.Named CASLFORMULA)


type ImportsWO = Set.Set (NODE_NAMEWO, (Maybe MorphismMap), HidingAndRequationList)
type SortsWO = Set.Set SORTWO
type RelsWO = Rel.Rel SORTWO
type PredsWO = Map.Map IdWO (Set.Set PredType)
type OpsWO = Map.Map IdWO (Set.Set OpType)
type SensWO = Set.Set SentenceWO

type ImportsMap = Map.Map String Imports
type SortsMap = Map.Map String Sorts
type RelsMap = Map.Map String Rels
type PredsMap = Map.Map String Preds
type OpsMap = Map.Map String Ops
type SensMap = Map.Map String Sens

type ImportsMapDGWO = Map.Map NODE_NAMEWO ImportsWO
type SortsMapDGWO = Map.Map NODE_NAMEWO SortsWO
type RelsMapDGWO = Map.Map NODE_NAMEWO RelsWO
type PredsMapDGWO = Map.Map NODE_NAMEWO PredsWO
type OpsMapDGWO = Map.Map NODE_NAMEWO OpsWO
type SensMapDGWO = Map.Map NODE_NAMEWO SensWO

type AllMaps = (ImportsMap, SortsMap, RelsMap, PredsMap, OpsMap, SensMap)

instance Show AllMaps where
  show (imports, sorts, rels, preds, ops, sens) =
    "Imports:\n" ++ show imports ++
    "\nSorts:\n" ++ show sorts ++
    "\nRelations:\n" ++ show rels ++
    "\nPredicates:\n" ++ show preds ++
    "\nOperators:\n" ++ show ops ++
    "\nSentences:\n" ++ show sens

diffMaps::
  (Sorts, Rels, Preds, Ops, Sens) ->
  (Sorts, Rels, Preds, Ops, Sens) ->
  (Sorts, Rels, Preds, Ops, Sens)
diffMaps
  (so1, re1, pr1, op1, se1)
  (so2, re2, pr2, op2, se2) =
    ( 
      Set.difference so1 so2,
      Rel.difference re1 re2,
      Map.difference pr1 pr2,
      Map.difference op1 op2,
      Set.difference se1 se2
    )
    
lookupMaps::
  SortsMap ->
  RelsMap ->
  PredsMap ->
  OpsMap ->
  SensMap ->
  String ->
  (Sorts, Rels, Preds, Ops, Sens)
lookupMaps sorts rels preds ops sens name =
    (
      Map.findWithDefault Set.empty name sorts,
      Map.findWithDefault Rel.empty name rels,
      Map.findWithDefault Map.empty name preds,
      Map.findWithDefault Map.empty name ops,
      Map.findWithDefault Set.empty name sens
    )
    
-- create a mapping of node-name -> Set of Sorts for all nodes
getSortsWithNodeNames::DGraph->SortsMap
getSortsWithNodeNames dg = getNodeNameMapping dg getNodeDeltaSorts Set.null

getSortsWithNodeDGNames::DGraph->Map.Map NODE_NAME Sorts
getSortsWithNodeDGNames dg = getNodeDGNameMapping dg getNodeDeltaSorts Set.null

getSortsWOWithNodeDGNamesWO::DGraph->SortsMapDGWO
getSortsWOWithNodeDGNamesWO dg =
  getNodeDGNameMappingWO dg getSortsFromNodeWithOrigins Set.null

-- create a mapping of node-name -> Relation of Sorts for all nodes
getRelationsWithNodeNames::DGraph->RelsMap
getRelationsWithNodeNames dg = getNodeNameMapping dg getNodeDeltaRelations Rel.null

getRelationsWithNodeDGNames::DGraph->Map.Map NODE_NAME Rels
getRelationsWithNodeDGNames dg = getNodeDGNameMapping dg getNodeDeltaRelations Rel.null

getRelationsWOWithNodeDGNamesWO::DGraph->RelsMapDGWO
getRelationsWOWithNodeDGNamesWO dg =
  getNodeDGNameMappingWO dg (getRelsFromNodeWithOrigins Nothing) Rel.null

getRelationsWOWithNodeDGNamesWOSMDGWO::DGraph->SortsMapDGWO->RelsMapDGWO
getRelationsWOWithNodeDGNamesWOSMDGWO dg sm =
  getNodeDGNameMappingWONP dg (\nodenamewo -> getRelsFromNodeWithOrigins (Map.lookup nodenamewo sm)) Rel.null
  
-- create a mapping of node-name -> Predicate-Mapping (PredName -> Set of PredType)
getPredMapsWithNodeNames::DGraph->PredsMap
getPredMapsWithNodeNames dg = getNodeNameMapping dg getNodeDeltaPredMaps Map.null

--debugging-function
findPredsByName::PredsMap->String->[(String, (Id.Id, Set.Set PredType))]
findPredsByName pm name =
  let
    nameid = stringToId name
  in
    foldl (\l (k, v) ->
      foldl (\l' (pid, v') ->
        if pid == nameid
          then
            l' ++ [(k, (pid, v'))]
          else
            l'
      ) l (Map.toList v)
    ) [] (Map.toList pm)

getPredMapsWithNodeDGNames::DGraph->Map.Map NODE_NAME Preds
getPredMapsWithNodeDGNames dg = getNodeDGNameMapping dg getNodeDeltaPredMaps Map.null

getPredMapsWOWithNodeDGNamesWO::DGraph->PredsMapDGWO
getPredMapsWOWithNodeDGNamesWO dg = getNodeDGNameMappingWO dg getPredsMapFromNodeWithOrigins Map.null 

--debugging-function
findPredsWODGByName::PredsMapDGWO->String->[(NODE_NAMEWO, (IdWO, Set.Set PredType))]
findPredsWODGByName pm name =
  let
    nameid = stringToId name
  in
    foldl (\l (k, v) ->
      foldl (\l' (pid, v') ->
        if (wonItem pid) == nameid
          then
            l' ++ [(k, (pid, v'))]
          else
            l'
      ) l (Map.toList v)
    ) [] (Map.toList pm)
    
-- create a mapping of node-name -> Operand-Mapping (OpName -> Set of OpType)
getOpMapsWithNodeNames::DGraph->OpsMap
getOpMapsWithNodeNames dg = getNodeNameMapping dg getNodeDeltaOpMaps Map.null

--debugging-function
findOpsByName::OpsMap->String->[(String, (Id.Id, Set.Set OpType))]
findOpsByName om name =
  let
    nameid = stringToId name
  in
    foldl (\l (k, v) ->
      foldl (\l' (oid, v') ->
        if oid == nameid
          then
            l' ++ [(k, (oid, v'))]
          else
            l'
      ) l (Map.toList v)
    ) [] (Map.toList om)

getOpMapsWithNodeDGNames::DGraph->Map.Map NODE_NAME Ops
getOpMapsWithNodeDGNames dg = getNodeDGNameMapping dg getNodeDeltaOpMaps Map.null

getOpMapsWOWithNodeDGNamesWO::DGraph->OpsMapDGWO
getOpMapsWOWithNodeDGNamesWO dg = getNodeDGNameMappingWO dg getOpsMapFromNodeWithOrigins Map.null 

-- get a mapping of node-name -> Set of Sentences (CASL-formulas)
getSentencesWithNodeNames::DGraph->SensMap
getSentencesWithNodeNames dg = getNodeNameMapping dg getNodeDeltaSentences Set.null

getSentencesWithNodeDGNames::DGraph->Map.Map NODE_NAME Sens
getSentencesWithNodeDGNames dg = getNodeDGNameMapping dg getNodeDeltaSentences Set.null

getSentencesWOWithNodeDGNamesWO::DGraph->SensMapDGWO
getSentencesWOWithNodeDGNamesWO dg = getNodeDGNameMappingWO dg getSensFromNodeWithOrigins Set.null

getAll::DGraph->AllMaps
getAll dg = (
  getNodeImportsNodeNames dg,
  getSortsWithNodeNames dg,
  getRelationsWithNodeNames dg,
  getPredMapsWithNodeNames dg,
  getOpMapsWithNodeNames dg,
  getSentencesWithNodeNames dg
  )

getExternalLibNames::DGraph->(Set.Set LIB_NAME)
getExternalLibNames =
  Set.fromList . map dgn_libname . filter isDGRef . map snd . Graph.labNodes

-- get all axioms
getAxioms::[Ann.Named a]->[Ann.Named a]
getAxioms l = filter (\(NamedSen {isAxiom = iA}) -> iA) l

-- get all non-axioms
getNonAxioms::[Ann.Named a]->[Ann.Named a]
getNonAxioms l = filter (\(NamedSen {isAxiom = iA}) -> not iA) l

isEmptyMorphism::(Morphism a b c)->Bool
isEmptyMorphism (Morphism ss ts sm fm pm _) =
  Map.null sm && Map.null fm && Map.null pm

isEmptyCASLMorphism::CASL.Morphism.Morphism () () ()->Bool
isEmptyCASLMorphism m = CASL.Sign.isSubSig (\_ _ -> True) (msource m) (mtarget m)

isEmptyMorphismMap::MorphismMap->Bool
isEmptyMorphismMap (sm,om,pm,hs) =
  (Map.null sm && Map.null om && Map.null pm && Set.null hs)

-- fetch the names of all nodes from wich sorts,rels, etc. are imported
-- this does not list all imports in the DGraph, just the ones that cause
-- sorts,rels, etc. to dissappear from a node
getNodeImportsNodeNames::DGraph->ImportsMap
getNodeImportsNodeNames dg = getNodeNameMapping dg (
  \dgr n -> Set.fromList $ 
   foldl (\names (from,node) ->
    let
      edges' = filter (\(a,b,_) -> (a == from) && (b==n)) $ Graph.labEdges dgr
      caslmorph = case edges' of
        [] -> emptyCASLMorphism
        (l:_) -> getCASLMorph l
      isglobal = case edges' of
        [] -> True
        ((_,_,e):_) -> case dgl_type e of
          (LocalDef) -> False
          _ -> True
      mmm = if isEmptyMorphism caslmorph
        then
          Nothing
        else
          (Just (makeMorphismMap caslmorph))
    in
      ((adjustNodeName ("AnonNode_"++(show from)) $ getDGNodeName node), mmm, ([],[]), isglobal):names
    ) [] $ inputLNodes dgr n ) Set.null
  
getNodeImportsNodeDGNamesWO::DGraph->ImportsMapDGWO --Map.Map NODE_NAMEWO (Set.Set (NODE_NAMEWO, Maybe MorphismMap))
getNodeImportsNodeDGNamesWO dg = getNodeDGNameMappingWO dg (
  \dgr n -> Set.fromList $ 
   foldl (\names (from,node) ->
    let
      edges' = filter (\(a,b,_) -> (a == from) && (b==n)) $ Graph.labEdges dgr
      caslmorph = case edges' of
        [] -> emptyCASLMorphism
        (l:_) -> getCASLMorph l
      mmm = if isEmptyMorphism caslmorph
        then
          Nothing
        else
          (Just (makeMorphismMap caslmorph))
    in
      ((mkWON (dgn_name node) from), mmm, ([],[])):names
    ) [] $ inputLNodes dgr n ) Set.null

switchTargetSourceMorph::Morphism () () ()->Morphism () () ()
switchTargetSourceMorph m =
  m { mtarget = msource m, msource = mtarget m }

getNodeAllImportsNodeDGNamesWOLL::
  DGraph
  ->Map.Map NODE_NAMEWO [(NODE_NAMEWO, Maybe DGLinkLab, Maybe MorphismMap)]
getNodeAllImportsNodeDGNamesWOLL dg = getNodeDGNameMappingWO dg (
  \dgr n -> 
    let
      incomming =
        (filter (\(_, tn, _) -> tn == n)) $ Graph.labEdges dgr
      incommingWN =
        map
          (\(fn,tn,iedge) ->
            case Graph.lab dgr fn of
              Nothing -> error "Corrupt Graph!"
              (Just inode) -> (fn,tn,iedge,inode)
          )
          incomming
    in
      foldl
        (\imports (fn, _, iedge, inode) ->
{-          let
            icaslmorph = getCASLMorph (undefined, undefined, iedge)
            caslmorph = case dgl_type iedge of 
              HidingDef -> switchTargetSourceMorph icaslmorph
              _ -> icaslmorph
            mm = makeMorphismMap caslmorph
            mmm = if isEmptyMorphismMap mm
              then
                Nothing
              else
                (Just mm) 
          in -}
            imports ++ [ ((mkWON (dgn_name inode) fn), Just iedge, Nothing) ]
        )
        []
        incommingWN
  )
  null

getNodeAllImportsNodeDGNamesWOLLo::
  DGraph
  ->Map.Map NODE_NAMEWO [(NODE_NAMEWO, Maybe DGLinkLab, Maybe MorphismMap)]
getNodeAllImportsNodeDGNamesWOLLo dg = getNodeDGNameMappingWO dg (
  \dgr n -> 
    foldl (\names (from,node) ->
      let
        edges' = filter (\(a,b,_) -> (a == from) && (b==n)) $ Graph.labEdges dgr
        mfirstedge = case edges' of
          (l:_) -> Just l
          _ -> Nothing
        mfirstll = case mfirstedge of
          Nothing -> Nothing
          (Just (_,_,ll)) -> Just ll
        caslmorph = case mfirstedge of
          (Just l) -> getCASLMorph l
          _ -> emptyCASLMorphism
        mmm = if isEmptyMorphism caslmorph
          then
            Nothing
          else
            (Just (makeMorphismMap caslmorph))
      in
        ((mkWON (dgn_name node) from), mfirstll, mmm):names
    ) [] (innNodes dgr n) )
    null
    
getNodeImportsNodeDGNames::DGraph->Map.Map NODE_NAME (Set.Set (NODE_NAME, Maybe MorphismMap))
getNodeImportsNodeDGNames dg = getNodeDGNameMapping dg (
  \dgr n -> Set.fromList $ 
   foldl (\names (from,node) ->
    let
      edges' = filter (\(a,b,_) -> (a == from) && (b==n)) $ Graph.labEdges dgr
      caslmorph = case edges' of
        [] -> emptyCASLMorphism
        (l:_) -> getCASLMorph l
      mmm = if isEmptyMorphism caslmorph
        then
          Nothing
        else
          (Just (makeMorphismMap caslmorph))
    in
      ((dgn_name node), mmm):names
    ) [] $ inputLNodes dgr n ) Set.null
                
adjustNodeName::String->String->String
adjustNodeName def [] = def
adjustNodeName _ name = name

-- get a set of all names for the nodes in the DGraph
getNodeNames::DGraph->(Set.Set (Graph.Node, String))
getNodeNames dg =
  fst $ foldl (\(ns, num) (n, node) ->
    (Set.insert (n, adjustNodeName ("AnonNode_"++(show num)) $ getDGNodeName node) ns, (num+1)::Integer)
    ) (Set.empty, 1) $ Graph.labNodes dg
    
-- | get two sets of node nums and names. first set are nodes, second are refs
getNodeNamesNodeRef::DGraph->(Set.Set (Graph.Node, String), Set.Set (Graph.Node, String))
getNodeNamesNodeRef dg =
  let
    lnodes = Graph.labNodes dg
    (nodes' , refs) = partition (\(_,n) -> not $ isDGRef n) lnodes
    nnames = map (\(n, node) -> (n, adjustNodeName ("AnonNode_"++(show n)) $ getDGNodeName node)) nodes'
    rnames = map (\(n, node) -> (n, adjustNodeName ("AnonRef_"++(show n)) $ getDGNodeName node)) refs
  in
    (Set.fromList nnames, Set.fromList rnames)
      
getNodeDGNamesNodeRef::DGraph->(Set.Set (Graph.Node, NODE_NAME), Set.Set (Graph.Node, NODE_NAME))
getNodeDGNamesNodeRef dg =
  let
    lnodes = Graph.labNodes dg
    (nodes' , refs) = partition (\(_,n) -> not $ isDGRef n) lnodes
    nnames = map (\(n, node) -> (n, dgn_name node)) nodes'
    rnames = map (\(n, node) -> (n, dgn_name node)) refs
  in
    (Set.fromList nnames, Set.fromList rnames)


-- go through a list and perform a function on each element that returns a Maybe
-- return the first value that is not Nothing
first::(a -> (Maybe b))->[a]->(Maybe b)
first _ [] = Nothing
first f (a:l) = let b = f a in case b of Nothing -> first f l; _ -> b 

-- searches for the origin of an attribute used in a node
-- the finder-function returns true, if the the attribute is 'true' for
-- the attribute-map for a node
findNodeNameFor::ImportsMap->(Map.Map String a)->(a->Bool)->String->(Maybe String)
findNodeNameFor importsMap attribMap finder name =
  let
    m_currentAttrib = Map.lookup name attribMap
    currentImports = Set.map (\(a,_,_,_) -> a) $ Map.findWithDefault Set.empty name importsMap
  in
    if (
      case m_currentAttrib of
        Nothing -> False
        (Just a) -> finder a
      ) then
        (Just name)
        else
        first (findNodeNameFor importsMap attribMap finder) $ Set.toList currentImports

-- lookup a sort starting with a given node (by name)
-- will traverse the importsMap while the sort is not found and
-- return the name of the [first] node that has this sort in its sort-set 
findNodeNameForSort::ImportsMap->SortsMap->SORT->String->(Maybe String)
findNodeNameForSort importsMap sortsMap sort name =
  findNodeNameFor importsMap sortsMap (Set.member sort) name

-- lookup the origin of a predication by id
-- not very usefull without specifying the argument-sorts
findNodeNameForPredication::ImportsMap->PredsMap->Id.Id->String->(Maybe String)
findNodeNameForPredication importsMap predsMap predId name =
  findNodeNameFor importsMap predsMap (\m -> Map.lookup predId m /= Nothing) name
  
-- lookup the origin of a predication by id and argument-sorts (PredType)
findNodeNameForPredicationWithSorts::ImportsMap->PredsMap->(Id.Id, PredType)->String->(Maybe String)
findNodeNameForPredicationWithSorts importsMap predsMap (predId, pt) name =
  findNodeNameFor importsMap predsMap 
    (\m ->  let predSet = Map.findWithDefault Set.empty predId m
      in Set.member pt predSet )
    name

-- lookup the origin of an operand    
findNodeNameForOperator::ImportsMap->OpsMap->Id.Id->String->(Maybe String)
findNodeNameForOperator importsMap opsMap opId name =
  findNodeNameFor importsMap opsMap (\m -> Map.lookup opId m /= Nothing) name
  
-- lookup the origin of an operand with OpType
findNodeNameForOperatorWithSorts::ImportsMap->OpsMap->(Id.Id, OpType)->String->(Maybe String)
findNodeNameForOperatorWithSorts importsMap opsMap (opId, ot) name =
  findNodeNameFor importsMap opsMap 
    (\m ->  let opSet = Map.findWithDefault Set.empty opId m
      in Set.member ot opSet )
    name
    
findNodeNameForOperatorWithFK::ImportsMap->OpsMap->(Id.Id, FunKind)->String->(Maybe String)
findNodeNameForOperatorWithFK importsMap opsMap (opId, fk) name =
  findNodeNameFor importsMap opsMap 
    (\m ->  let opSet = Map.findWithDefault Set.empty opId m
      in not $ null $ filter (\(OpType ofk _ _) -> ofk == fk) $ Set.toList opSet )
    name


findNodeNameForSentenceName::ImportsMap->SensMap->String->String->(Maybe String)
findNodeNameForSentenceName importsMap sensMap sName name =
  findNodeNameFor importsMap sensMap (\n -> not $ Set.null $ Set.filter (\n' -> (senName n' ) == sName) n) name
  
findNodeNameForSentence::ImportsMap->SensMap->CASLFORMULA->String->(Maybe String)
findNodeNameForSentence importsMap sensMap s name =
  findNodeNameFor importsMap sensMap (\n -> not $ Set.null $ Set.filter (\n' -> (sentence n' ) == s) n) name
  
buildCASLSentenceDiff::(Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof))->(Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof))->(Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof))
buildCASLSentenceDiff = OMap.difference

buildCASLSignDiff::CASLSign->CASLSign->CASLSign
buildCASLSignDiff = diffSig

emptyCASLMorphism::(CASL.Morphism.Morphism () () ())
emptyCASLMorphism = CASL.Morphism.Morphism (emptySign ()) (emptySign ()) Map.empty Map.empty Map.empty ()
    
emptyCASLGMorphism::Logic.Grothendieck.GMorphism
emptyCASLGMorphism = Logic.Grothendieck.gEmbed (Logic.Grothendieck.G_morphism CASL emptyCASLMorphism)

makeCASLGMorphism::(CASL.Morphism.Morphism () () ())->Logic.Grothendieck.GMorphism
makeCASLGMorphism m = Logic.Grothendieck.gEmbed (Logic.Grothendieck.G_morphism CASL m)

emptyCASLSign::CASLSign
emptyCASLSign = emptySign ()


-- | create a node containing only the local attributes of this node by stripping
-- the attributes of the second node
buildCASLNodeDiff::DGNodeLab->DGNodeLab->DGNodeLab
buildCASLNodeDiff
  node1@(DGNode { dgn_theory = th1})
  (DGNode { dgn_theory = th2}) =
  let
    sens1 = (\(G_theory _ _ sens) -> (cast sens)::(Maybe (Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof)))) th1
    sens2 = (\(G_theory _ _ sens) -> (cast sens)::(Maybe (Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof)))) th2
    sign1 = (\(G_theory _ sign _) -> (cast sign)::(Maybe CASLSign)) th1
    sign2 = (\(G_theory _ sign _) -> (cast sign)::(Maybe CASLSign)) th2
  in
    case (sens1, sens2, sign1, sign2) of
      (Just se1, Just se2, Just si1, Just si2) ->
        let
          sediff = buildCASLSentenceDiff se1 se2
          sidiff = buildCASLSignDiff si1 si2
          theo = G_theory CASL sidiff sediff
        in
          node1 { dgn_theory = theo }
      _ ->
        error "This function can only handle CASL-related DGNodeLabS..."   
buildCASLNodeDiff n _ = n -- error "Either one or both Nodes are DGRefs. I cannot handle DGRefs..."

stripCASLMorphism::DGNodeLab->(CASL.Morphism.Morphism () () ())->DGNodeLab
stripCASLMorphism
  n@(DGNode { dgn_theory = th } )
  (CASL.Morphism.Morphism { CASL.Morphism.fun_map = fm, CASL.Morphism.pred_map = pm }) =
    let
      mcsi = (\(G_theory _ sign _) -> (cast sign)::(Maybe CASLSign)) th
      mcse = (\(G_theory _ _ sens) -> (cast sens)::(Maybe (Prover.ThSens CASLFORMULA (AnyComorphism, BasicProof)))) th
    in case mcsi of
      (Just (Sign ss sr om ao oldpm vm se ev ga ei)) ->
        let
          funlist = (map (\(_, (f, _)) -> f) $ Map.toList fm)::[Id.Id]
          predlist = (map (\(_, p) -> p) $ Map.toList pm)::[Id.Id]
          newpredmap = foldl (\nmap' id' ->
            Map.filterWithKey (\k _ -> k /= id' ) nmap'
            ) oldpm predlist
          newopmap = foldl (\nmap' id' ->
            Map.filterWithKey (\k _ -> k /= id' ) nmap'
            ) om funlist
          newassocmap = foldl (\nmap' id' ->
            Map.filterWithKey (\k _ -> k /= id' ) nmap'
            ) ao funlist
        in  case mcse of
            (Just csens) -> n { dgn_theory = (G_theory CASL (Sign ss sr newopmap newassocmap newpredmap vm se ev ga ei) csens) }
            _ -> error "Could not cast sentences to (ThSens CASLFORMULA) (but a CASLSign was cast... (wierd!))"
      Nothing -> n  -- maybe this node is not CASL-related... leave it as is
stripCASLMorphism n@(DGRef {}) _ = n -- can DGRefS have a morphism from another node in the graph ?


stripCASLMorphisms::DGraph->(Graph.LNode DGNodeLab)->(Graph.LNode DGNodeLab)
stripCASLMorphisms dg (n, node) =
  case node of
    (DGRef {}) -> (n, node) -- no need to do this for a reference...
    _ ->
      let
        incoming = filter ( \(_,tn,_) -> n == tn ) $ Graph.labEdges dg
        {- imports = filter ( \(_,_,iedge) ->
          case iedge of
            (DGLink _ t _) ->
              case t of
                LocalDef -> True
                GlobalDef -> True
                HidingDef -> True
                _ -> False
          ) incoming -}
        morphisms = map ( \(_,_,e) -> dgl_morphism e) incoming
      in (n,
        foldl (\newnode gmorph ->
          let
            mcaslmorph = (\(GMorphism _ _ morph) -> (cast morph)::(Maybe (CASL.Morphism.Morphism () () ()))) gmorph
          in  case mcaslmorph of
            (Just caslmorph) -> stripCASLMorphism newnode caslmorph
            _ -> newnode
            ) node morphisms)
   
-- Morphism-presentation with Strings (from xml)
-- Strings need to be looked up from their representation
-- to create an Id
type MorphismMapS = (
    Map.Map String String
  , Map.Map (String,OpType) (String,OpType)
  , Map.Map (String,PredType) (String,PredType)
  , Set.Set String
  )
  
morphismMapToMMS::MorphismMap->MorphismMapS
morphismMapToMMS (sm, om, pm, hs) =
  (
      Map.fromList
        (
          map
            (\(a,b) -> (show a, show b))
            (Map.toList sm)
        )
    , Map.fromList
        (
          map
            (\((a,at),(b,bt)) -> ((show a, at), (show b, bt)))
            (Map.toList om)
        )
    , Map.fromList
        (
          map
            (\((a,at),(b,bt)) -> ((show a, at), (show b, bt)))
            (Map.toList pm)
        )
    , Set.map
        show
        hs
  )

type MorphismMap = (
    (Map.Map SORT SORT)
    ,(Map.Map (Id.Id,OpType) (Id.Id,OpType))
    ,(Map.Map (Id.Id,PredType) (Id.Id,PredType))
    ,(Set.Set SORT)
    )
    
type MorphismMapWO = (
    (Map.Map SORTWO SORTWO)
    ,(Map.Map (IdWO,OpType) (IdWO, OpType))
    ,(Map.Map (IdWO,PredType) (IdWO,PredType))
    ,(Set.Set SORTWO)
    )


type RequationList = [ ( (String, String), (String, String) ) ]

type HidingAndRequationList = ([String], RequationList)

-- string is 'from'
type RequationListList = [(String, HidingAndRequationList)]

-- string is 'where'
type RequationMap = Map.Map String RequationListList

hidingAndRequationListToMorphismMap::
  HidingAndRequationList
  ->MorphismMap
hidingAndRequationListToMorphismMap
  (hidden, requationlist) =
    (
        Map.fromList (map (\((_,a),(_,b)) -> (stringToId a, stringToId b)) requationlist)
      , Map.empty
      , Map.empty
      , Set.fromList (map stringToId hidden)
    )
    
createHidingString::CASLSign->String
createHidingString (Sign sortset _ opmap _ predmap _ _ _ _ _) =
  let
    hidden = map show (Set.toList sortset) ++
       map show (Map.keys opmap) ++
       map show (Map.keys predmap)
  in  implode ", " hidden

getSymbols::CASLSign->[Id.Id]
getSymbols (Sign sortset _ opmap _ predmap _ _ _ _ _) =
  (Set.toList sortset) ++ (Map.keys opmap) ++ (Map.keys predmap)

-- hiding is currently wrong because this function does only check 
-- if any symbols dissappear in the target - this happens also when renaming...
makeMorphismMap_o::(Morphism () () ())->MorphismMap
makeMorphismMap_o (Morphism ssource starget sortmap funmap predmap _) =
  let
    newfunmap = Map.fromList $ map (
      \((sid,sot),(tid,tfk)) ->
        -- Hets sets opKind to Partial on morphism... why ?
        -- resulting signatures have Total operators...
        ((sid,(sot { opKind = Total }) ), (tid,
          OpType
            tfk
            (map (\id' -> Map.findWithDefault id' id' sortmap) (opArgs sot))
            ((\id' -> Map.findWithDefault id' id' sortmap) (opRes sot))
          ) ) ) $ Map.toList funmap
    newpredmap = Map.fromList $ map (
      \((sid, spt),tid) ->
        ((sid, spt), (tid,
          PredType (map (\id' -> Map.findWithDefault id' id' sortmap) (predArgs spt))
        ) ) ) $ Map.toList predmap
  in
    (sortmap, newfunmap, newpredmap, Set.fromList $ getSymbols $ diffSig ssource starget)

makeMorphismMap::(Morphism () () ())->MorphismMap
makeMorphismMap m =
  let
    ssign = msource m
    tsign = mtarget m
    sortmap = sort_map m
    predmap = pred_map m
    opmap = fun_map m
    hiddeninit = getSymbols ssign
    -- all (translated) symbols from the source (
    (sms, hiddens) =
      Set.fold
        (\s (sms', hs) ->
          let
            newsort = Map.findWithDefault s s sortmap
          in
            -- check whether the translated sort appears in the target
            if Set.member newsort (sortSet tsign)
              then
--                Debug.Trace.trace ("Found Sort in Target : " ++ show newsort)
                -- if it does, it is not hidden
                (sms'
                  {
                    -- delete original sort
                    sortSet = Set.delete s (sortSet sms')
                  }, Data.List.delete s hs)
              else
--                Debug.Trace.trace ("Sort is hidden : " ++ show newsort)
                (sms', hs)
        )
        (ssign, hiddeninit)
        (sortSet ssign)
    (smp, hiddenp) =
     Map.foldWithKey
      (\pid ps (smp', hp) ->
        Set.fold
          (\pt (smp'', hp') ->
            case Map.lookup (pid, pt) predmap of
              Nothing ->
                (smp'', hp')
              (Just newpid) ->
                let
                  currentsourcepts = Map.findWithDefault Set.empty pid (predMap smp'')
                  currentpts = Map.findWithDefault Set.empty newpid (predMap tsign)
                  conpt = convertPredType pt
                in
                  if
                    Set.member
                      conpt
                      currentpts
                    then
 --                     Debug.Trace.trace ("Found Predicate in Target : " ++ show newpid) $
                      (smp''
                        {
                          predMap =
                            Map.insert
                              pid
                              (Set.delete pt currentsourcepts)
                              (predMap smp'')
                        }, Data.List.delete pid hp')
                    else
--                      Debug.Trace.trace ("Predicate is hidden : " ++ show newpid) $
                      (smp'', hp')
          )
          (smp', hp)
          ps
      )
      (sms, hiddens)
      (predMap ssign)
    (smo, hiddeno) =
     Map.foldWithKey
      (\oid os (smo', ho) ->
        Set.fold
          (\ot (smo'', ho') ->
            let
              (newoid, newfk) =
                case lookupOp (oid, ot) of
                  Nothing ->
                    (oid, opKind ot)
                  (Just x) -> x
              currentsourceots = Map.findWithDefault Set.empty oid (opMap smo'')
              currentots = Map.findWithDefault Set.empty newoid (opMap tsign)
              conot = (convertOpType ot) { opKind = newfk }
            in
              if
                Set.member
                  conot
                  currentots
                then
--                  Debug.Trace.trace ("Found Operator in Target : " ++ show newoid ++ " was ( " ++ show oid ++ ")" ++ show opmap) $
                  (smo''
                    {
                      opMap =
                        Map.insert
                          oid
                          (Set.delete ot currentsourceots)
                          (Map.delete oid (opMap smo''))
                    }, Data.List.delete oid ho')
                else
--                  Debug.Trace.trace ("Operator is hidden : " ++ show newoid) $
                  (smo'', ho')
          )
          (smo', ho)
          os
      )
      (smp, hiddenp)
      (opMap ssign)
    sma =
     Map.foldWithKey
      (\oid os sma' ->
        Set.fold
          (\ot sma'' ->
            case lookupOp (oid, ot) of
              Nothing ->
                sma''
              (Just (newoid, newfk)) ->
                let
                  currentsourceots = Map.findWithDefault Set.empty oid (opMap sma'')
                  currentots = Map.findWithDefault Set.empty newoid (assocOps tsign)
                  conot = (convertOpType ot) { opKind = newfk }
                in
                  if
                    Set.member
                      conot
                      currentots
                    then
     --                 Debug.Trace.trace ("Found Operator in Target (A) : " ++ show newoid) $
                      sma''
                        {
                          assocOps =
                            Map.insert
                              oid
                              (Set.delete ot currentsourceots)
                              (assocOps sma'')
                        }
                    else
--                      Debug.Trace.trace ("Operator is hidden (A) : " ++ show newoid) $
                      sma''
          )
          sma'
          os
      )
      smo
      (assocOps ssign)
    newopmap =
      Map.fromList $
        map
          (\((sid,sot),(tid,tfk)) ->
          -- Hets sets opKind to Partial on morphism... why ?
          -- resulting signatures have Total operators...
            ( (sid, (sot { opKind = Total }) ), (tid, (convertOpType sot  { opKind = tfk }) ) )
          )
          (Map.toList opmap)
    newpredmap =
      Map.fromList $
        map
          ( \( (sid, spt), tid ) -> ( (sid, spt), (tid, convertPredType spt) ) ) 
          (Map.toList predmap)
  in
--    Debug.Trace.trace ("Making MM by " ++ (show opmap) ++ " from " ++ (show ssign) ++ " -> " ++ (show tsign) ++ "...")
--    $
--    Debug.Trace.trace ("Hiding : " ++ (show $ getSymbols sma) ++ " or " ++ show hiddeno)
      (sortmap, newopmap, newpredmap, Set.fromList hiddeno)
  where
    convertArgs::[SORT]->[SORT]
    convertArgs = map (\x -> Map.findWithDefault x x (sort_map m))
    convertPredType::PredType->PredType
    convertPredType p = p { predArgs = convertArgs (predArgs p) }
    convertOpType::OpType->OpType
    convertOpType o =
      o
        {
            opArgs = convertArgs (opArgs o)
          , opRes = Map.findWithDefault (opRes o) (opRes o) (sort_map m)
        }
    lookupOp::(Id.Id, OpType)->Maybe (Id.Id, FunKind)
    lookupOp (oid, ot) =
      case Map.lookup (oid, ot) (fun_map m) of
        (Just x) -> (Just x)
        Nothing ->
          case
            Map.lookup
              (oid, ot { opKind = (if (opKind ot) == Total then Partial else Total) })
              (fun_map m)
            of
              (Just x) -> (Just x)
              Nothing -> Nothing
          
    
removeMorphismSorts::MorphismMap->Sorts->Sorts
removeMorphismSorts (sm,_,_,_) sorts =
  let
    msorts = Map.elems sm
  in
    Set.filter (\s -> not $ elem s msorts) sorts
    
addMorphismSorts::MorphismMap->Sorts->Sorts
addMorphismSorts (sm,_,_,_) sorts =
  let
    msorts = Map.elems sm
  in  
    Set.union sorts $ Set.fromList msorts
    
removeMorphismOps::MorphismMap->Ops->Ops
removeMorphismOps (_,om,_,_) ops =
  let
    mops = map fst $ Map.elems om
  in
    Map.filterWithKey (\k _ -> not $ elem k mops) ops
    
addMorphismOps::MorphismMap->Ops->Ops
addMorphismOps (_,om,_,_) ops =
  let
    mops = Map.elems om
  in
    foldl (\newmap (i,ot) ->
      Map.insert
        i
        (Set.union
          (Map.findWithDefault Set.empty i newmap)
          (Set.singleton ot)
        )
        newmap
      ) ops mops 
    
removeMorphismPreds::MorphismMap->Preds->Preds
removeMorphismPreds (_,_,pm,_) preds =
  let
    mpreds = map fst $ Map.elems pm
  in
    Map.filterWithKey (\k _ -> not $ elem k mpreds) preds 
  
addMorphismPreds::MorphismMap->Preds->Preds
addMorphismPreds (_,_,pm,_) preds =
  let
    mpreds = Map.elems pm
  in
    foldl (\newmap (i,pt) ->
      Map.insert
        i
        (Set.union
          (Map.findWithDefault Set.empty i newmap)
          (Set.singleton pt)
        )
        newmap
      ) preds mpreds 
 
-- create a Morphism from a MorphismMap (stores hidden symbols in source-sign -> sortSet 
morphismMapToMorphism::MorphismMap->(Morphism () () ())
morphismMapToMorphism (sortmap, funmap, predmap, hs) =
  let
    mfunmap = Map.fromList $ map (\((sid, sot),t) -> ((sid, sot { opKind = Partial }),t)) $ Map.toList $ Map.map (\(tid,(OpType fk _ _)) ->
      (tid, fk) ) funmap
    mpredmap = Map.map (\(tid,_) -> tid ) predmap
    -- this is just a workaround to store the hiding-set
    sourceSignForHiding = emptyCASLSign { sortSet = hs }
  in
    Morphism
      {
          msource = sourceSignForHiding
        , mtarget = (emptySign ())
        , sort_map = sortmap
        , fun_map = mfunmap
        , pred_map = mpredmap
        , extended_map = ()
      }
    
applyMorphHiding::MorphismMap->[Id.Id]->MorphismMap
applyMorphHiding mm [] = mm
applyMorphHiding (sortmap, funmap, predmap, hidingset) hidings =
  (
     Map.filterWithKey (\sid _ -> not $ elem sid hidings) sortmap
    ,Map.filterWithKey (\(sid,_) _ -> not $ elem sid hidings) funmap
    ,Map.filterWithKey (\(sid,_) _ -> not $ elem sid hidings) predmap
    ,hidingset
  )
  
buildMorphismSignO::MorphismMap->[Id.Id]->CASLSign->CASLSign
buildMorphismSignO
  (mmsm, mmfm, mmpm, _) 
  hidings
  sourcesign =
  let
    (Sign
      sortset
      sortrel
      opmap
      assocops
      predmap
      varmap
      sens
      envdiags
      ga
      ext
      ) = applySignHiding sourcesign hidings
  in
    Sign
      (Set.map
        (\origsort ->
          Map.findWithDefault origsort origsort mmsm
        )
        sortset)
      (Rel.fromList $ map (\(a, b) ->
        (Map.findWithDefault a a mmsm
        ,Map.findWithDefault b b mmsm)
        ) $ Rel.toList sortrel)
      (foldl (\mappedops (sid, sopts) ->
        foldl (\mo sot ->
          case Map.lookup (sid, sot) mmfm of
            Nothing -> mo
            (Just (mid, mot)) ->
              Map.insertWith (Set.union) mid (Set.singleton mot) mo
          ) mappedops $ Set.toList sopts
        ) Map.empty $ Map.toList opmap)
      (foldl (\mappedops (sid, sopts) ->
        foldl (\mo sot ->
          case Map.lookup (sid, sot) mmfm of
            Nothing -> mo
            (Just (mid, mot)) ->
              Map.insertWith (Set.union) mid (Set.singleton mot) mo
          ) mappedops $ Set.toList sopts
        ) Map.empty $ Map.toList assocops)
      (foldl (\mappedpreds (sid, sprts) ->
        foldl (\mp spt ->
          case Map.lookup (sid, spt) mmpm of
            Nothing -> mp
            (Just (mid, mpt)) ->
              Map.insertWith (Set.union) mid (Set.singleton mpt) mp
          ) mappedpreds $ Set.toList sprts
        ) Map.empty $ Map.toList predmap)
      (Map.map (\vsort -> Map.findWithDefault vsort vsort mmsm) varmap)
      sens
      envdiags
      ga
      ext

buildMorphismSign::Morphism () () ()->Set.Set SORT->CASLSign->CASLSign
buildMorphismSign morphism hidingSet sign =
  let
    sortshide = Set.filter (\x -> not $ Set.member x hidingSet) (sortSet sign)
    relhide =
      Rel.fromList $
        filter
          (\(a,b) ->
            (not $ Set.member a hidingSet) && (not $ Set.member b hidingSet)
          )
          (Rel.toList (sortRel sign))
    predshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSet) (predMap sign)
    opshide =
      Map.filterWithKey
        (\k _ ->
            not $ Set.member k hidingSet
        )
      (opMap sign)
    assocshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSet) (assocOps sign)
    msorts =  
      Set.map
        (\s ->
          case Map.lookup s (sort_map morphism) of
            Nothing -> s
            (Just ms) -> ms
        )
        sortshide
    mrel =
     Rel.fromList $
      map
        (\(a, b) ->
          let
            na = case Map.lookup a (sort_map morphism) of
              Nothing -> a
              (Just ma) -> ma
            nb = case Map.lookup b (sort_map morphism) of
              Nothing -> b
              (Just mb) -> mb
         in
          (na, nb)
        )
        (Rel.toList relhide)
    mpreds =
      Map.foldWithKey
        (\pid ps mpm ->
          let
            mpreds' =
              map
                (\pt ->
                  case Map.lookup (pid, pt) (pred_map morphism) of
                    (Just mpid) -> (mpid, pt)
                    _ -> (pid, pt)
                )
                (Set.toList ps)
          in
            foldl
              (\mpm' (mpid, pt) ->
                let
                  oldset = Map.findWithDefault Set.empty mpid mpm'
                  newset = Set.union oldset (Set.singleton pt)
                in
                  Map.insert mpid newset mpm'
              )
              mpm
              mpreds'
        )
        (Map.empty)
        predshide
    mops =
      Map.foldWithKey
        (\oid os mom ->
          let
            mops' =
              map
                (\ot ->
                  case Map.lookup (oid, ot) (fun_map morphism) of
                    (Just (moid, fk)) -> (moid, ot { opKind = fk})
                    _ -> (oid, ot)
                )
                (Set.toList os)
          in
            foldl
              (\mom' (moid, ot) ->
                let
                  oldset = Map.findWithDefault Set.empty moid mom'
                  newset = Set.union oldset (Set.singleton ot)
                in
                  Map.insert moid newset mom'
              )
              mom
              mops'
        )
        (Map.empty)
        opshide
    mass =
      Map.foldWithKey
        (\oid os mam ->
          let
            mass' =
              map
                (\ot ->
                  case Map.lookup (oid, ot) (fun_map morphism) of
                    (Just (moid, fk)) -> (moid, ot { opKind = fk})
                    _ -> (oid, ot)
                )
                (Set.toList os)
          in
            foldl
              (\mam' (moid, ot) ->
                let
                  oldset = Map.findWithDefault Set.empty moid mam'
                  newset = Set.union oldset (Set.singleton ot)
                in
                  Map.insert moid newset mam'
              )
              mam
              mass'
        )
        (Map.empty)
        assocshide
    msign =
      sign
        {
            sortSet = msorts
          , sortRel = mrel
          , predMap = mpreds
          , opMap = mops
          , assocOps = mass
        }
  in
      msign

  
applySignHiding::CASLSign->[Id.Id]->CASLSign
applySignHiding 
  (Sign sortset sortrel opmap assocops predmap varmap sens envdiags ga ext)
  hidings =
  Sign
    (Set.filter (not . flip elem hidings) sortset)
    (Rel.fromList $ filter (\(id' ,_) -> not $ elem id' hidings) $ Rel.toList sortrel)
    (Map.filterWithKey (\sid _ -> not $ elem sid hidings) opmap)
    (Map.filterWithKey (\sid _ -> not $ elem sid hidings) assocops)
    (Map.filterWithKey (\sid _ -> not $ elem sid hidings) predmap)
    (Map.filter (\varsort -> not $ elem varsort hidings) varmap)
    sens
    envdiags
    ga
    ext

-- | Instance of Read for IdS           
instance Read Id.Id where
  readsPrec _ ('[':s) =
    let
      (tokens, rest) = spanEsc (not . (flip elem "[]")) s
      tokenl = breakIfNonEsc "," tokens
      token = map (\str -> Id.Token (trimString str) Id.nullRange) tokenl
      idl = breakIfNonEsc "," rest
      ids = foldl (\ids' str ->
        case ((readsPrec 0 (trimString str))::[(Id.Id, String)]) of
          [] -> error ("Unable to parse \"" ++ str ++ "\"")
          ((newid,_):_) -> ids' ++ [newid]
          ) [] idl
    in
      case (trimString rest) of
        (']':_) -> [(Id.Id token [] Id.nullRange, "")]
        _ -> [(Id.Id token ids Id.nullRange, "")]
      
  readsPrec _ _ = []

escapeForId::String->String
escapeForId [] = []
escapeForId ('[':r) = "\\[" ++ escapeForId r
escapeForId (']':r) = "\\]" ++ escapeForId r
escapeForId (',':r) = "\\," ++ escapeForId r
escapeForId (' ':r) = "\\ " ++ escapeForId r
escapeForId (c:r) = c:escapeForId r

-- | creates a parseable representation of an Id (see Read-instance)
idToString::Id.Id->String
idToString (Id.Id toks ids _) =
                "[" ++
                (implode "," (map (\t -> escapeForId $ Id.tokStr t) toks)) ++
                (implode "," (map idToString ids)) ++
                "]"
                
-- this encapsulates a node_name in an id
nodeNameToId::NODE_NAME->Id.Id
nodeNameToId (s,e,n) = Id.mkId [s,(stringToSimpleId e),(stringToSimpleId (show n))]

-- this reads back an encapsulated node_name
idToNodeName::Id.Id->NODE_NAME
idToNodeName (Id.Id toks _ _) = (toks!!0, show (toks!!1), read (show (toks!!2)))

getSortSet::DGraph->Node->Set.Set SORT
getSortSet dg n =
  getFromCASLSignM dg n sortSet

-- map every node to a map of every input node to a set of symbols *hidden*
-- when importing from the input node
type HidingMap = Map.Map Graph.Node (Map.Map Graph.Node (Set.Set SORT))

-- add node 1 to node 2
addSignsAndHideSet::DGraph->Set.Set SORT->Node->Node->DGNodeLab
addSignsAndHideSet dg hidingSetForSource n1 n2 =
  let
    n1dgnl = case Graph.lab dg n1 of
      Nothing -> error ("No such Node! " ++ (show n1))
      (Just x) -> x
    n2dgnl = case Graph.lab dg n2 of
      Nothing -> error ("No such Node! " ++ (show n2))
      (Just x) -> x
    sign1 =  getJustCASLSign $ getCASLSign (dgn_sign n1dgnl)
    sign2 =  getJustCASLSign $ getCASLSign (dgn_sign n2dgnl)
    asign = CASL.Sign.addSig (\_ _ -> ()) sign1 sign2
    sortshide = Set.filter (\x -> not $ Set.member x hidingSetForSource) (sortSet asign)
    relhide =
      Rel.fromList $
        filter
          (\(a,b) ->
            (not $ Set.member a hidingSetForSource) && (not $ Set.member b hidingSetForSource)
          )
          (Rel.toList (sortRel asign))
    predshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSetForSource) (predMap asign)
    opshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSetForSource) (opMap asign)
    assocshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSetForSource) (assocOps asign)
    signhide =
      asign
        {
            sortSet = sortshide
          , sortRel = relhide
          , predMap = predshide
          , opMap = opshide
          , assocOps = assocshide
        }
    newnodel =
      n2dgnl
        {
          dgn_theory = G_theory CASL signhide (Prover.toThSens [])
        }
  in
{-    Debug.Trace.trace
      ("--==!! Created new node from " ++ (show sign1) ++ " --==!! and !!==-- " ++ (show sign2) ++ " --==!! -> !!==-- " ++ (show asign) ++ " !!==-- ") -}
      newnodel

addSignsAndHideWithMorphism::DGraph->Set.Set SORT->Morphism () () ()->Node->Node->DGNodeLab
addSignsAndHideWithMorphism dg hiding mm n1 n2 =
  let
    n1dgnl = case Graph.lab dg n1 of
      Nothing -> error ("No such Node! " ++ (show n1))
      (Just x) -> x
    n2dgnl = case Graph.lab dg n2 of
      Nothing -> error ("No such Node! " ++ (show n2))
      (Just x) -> x
    sign1 =  getJustCASLSign $ getCASLSign (dgn_sign n1dgnl)

    sign2 =  getJustCASLSign $ getCASLSign (dgn_sign n2dgnl)

    msign = buildMorphismSign mm hiding sign1

    asign = CASL.Sign.addSig (\_ _ -> ()) msign sign2

    newnodel =
      n2dgnl
        {
          dgn_theory = G_theory CASL asign (Prover.toThSens [])
        }
  in
{-    Debug.Trace.trace
      ("--==!! Created new node from " ++ (show (dgn_name n1dgnl)) ++ " " ++ (show sign1) ++ " --==!! ##and## !!==-- " ++ (show (dgn_name n2dgnl)) ++ " " ++ (show sign2) ++ " --==!! ##--## !!==-- " ++ (show hiding) ++ " --==!! ##++## !!==-- " ++ (show msign) ++ " --==!! ##->## !!==-- " ++ (show asign) ++ " !!==-- ") -}
      newnodel



-- add node 1 to node 2
addSignsAndHide::DGraph->HidingMap->Node->Node->DGraph
addSignsAndHide dg hidingMap n1 n2 =
  let
    n1dgnl = case Graph.lab dg n1 of
      Nothing -> error ("No such Node! " ++ (show n1))
      (Just x) -> x
    n2dgnl = case Graph.lab dg n2 of
      Nothing -> error ("No such Node! " ++ (show n2))
      (Just x) -> x
    -- n2 is the target
    hidingMapForNode = Map.findWithDefault Map.empty n2 hidingMap
    -- n1 is the source
    hidingSetForSource = Map.findWithDefault Set.empty n1 hidingMapForNode
    sign1 =  getJustCASLSign $ getCASLSign (dgn_sign n1dgnl)
    sign2 =  getJustCASLSign $ getCASLSign (dgn_sign n2dgnl)
    asign = CASL.Sign.addSig (\_ _ -> ()) sign1 sign2
    sortshide = Set.filter (\x -> not $ Set.member x hidingSetForSource) (sortSet asign)
    relhide =
      Rel.fromList $
        filter
          (\(a,b) ->
            (not $ Set.member a hidingSetForSource) && (not $ Set.member b hidingSetForSource)
          )
          (Rel.toList (sortRel asign))
    predshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSetForSource) (predMap asign)
    opshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSetForSource) (opMap asign)
    assocshide = Map.filterWithKey (\k _ -> not $ Set.member k hidingSetForSource) (assocOps asign)
    signhide =
      asign
        {
            sortSet = sortshide
          , sortRel = relhide
          , predMap = predshide
          , opMap = opshide
          , assocOps = assocshide
        }
    newnodel =
      n2dgnl
        {
          dgn_theory = G_theory CASL signhide (Prover.toThSens [])
        }
  in
    Debug.Trace.trace ("HidingSet for " ++ show n1 ++ " -> "  ++ show n2 ++ " : " ++ show hidingSetForSource) $ Graph.insNode (n2, newnodel) (Graph.delNode n2 dg)


addSigns::DGraph->Node->Node->DGraph
addSigns dg n1 n2 =
  let
    n1dgnl = case Graph.lab dg n1 of
      Nothing -> error ("No such Node! " ++ (show n1))
      (Just x) -> x
    n2dgnl = case Graph.lab dg n2 of
      Nothing -> error ("No such Node! " ++ (show n2))
      (Just x) -> x
    sign1 =  getJustCASLSign $ getCASLSign (dgn_sign n1dgnl)
    sign2 =  getJustCASLSign $ getCASLSign (dgn_sign n2dgnl)
    asign = CASL.Sign.addSig (\_ _ -> ()) sign1 sign2
    newnodel = n2dgnl {
      dgn_theory =
        (\(G_theory _ _ thsens) -> G_theory CASL asign (Prover.toThSens [])) (dgn_theory n2dgnl)
      }
      
  in
    Graph.insNode (n2, newnodel) (Graph.delNode n2 dg)

data SortTrace =
    SortNotFound
  | ST
    {
        st_sort :: SORT
      , st_lib_name :: LIB_NAME
      , st_node :: Graph.Node
      , st_branches :: [SortTrace]
    }

displaySortTrace::String->SortTrace->String
displaySortTrace p SortNotFound = p ++ "_|_"
displaySortTrace
  p
  (ST { st_sort = s, st_lib_name = ln, st_node = n, st_branches = b }) =
  p ++ (show s) ++ " in " ++ (show ln) ++ ":" ++ (show n) 
    ++ 
    (if null b
      then
        ""
      else
        (concat
          (map
            (\branch -> "\n" ++ (displaySortTrace (p++"  ") branch) ) 
            b
          )
        )
    )

instance Show SortTrace where
  show = displaySortTrace ""

buildSortTraceFor::
  LibEnv
  ->LIB_NAME
  ->[(LIB_NAME, Graph.Node)]
  ->SORT
  ->Graph.Node
  ->SortTrace
buildSortTraceFor
  lenv
  ln
  visited
  s
  n =
  let
    dg =
      devGraph
        $ Map.findWithDefault
          (error ((show ln) ++ ": no such Library in Environment!"))
          ln
          lenv
    node =
      fromMaybe
        (error ( (show n) ++ "No such node in DevGraph!") )
        (Graph.lab dg n)
    caslsign = getJustCASLSign $ getCASLSign (dgn_sign node)
    sorts = sortSet caslsign
    newvisited = (ln, n):visited
    incoming =
      filter
        (\(from,_) ->
          (not (elem from (map snd (filter (\(ln',_) -> ln' == ln ) newvisited))))
        )
        $ map (\(from,_,ll) -> (from, ll)) $ Graph.inn dg n
    incoming_sorttrans =
      map
        (\(from, ll) ->
          let
            caslmorph = getCASLMorphLL ll
            newsort = sortBeforeMorphism caslmorph s
          in
            (from, newsort)
        )
        incoming
    reflib = dgn_libname node
    refnode = dgn_node node
    nexttraces =
      if
        isDGRef node
          then
            [(buildSortTraceFor lenv reflib newvisited s refnode)]
          else
            map
              (\(nodenum, newsort) ->
                buildSortTraceFor lenv ln newvisited newsort nodenum
              )
              incoming_sorttrans
  in
    if Set.member s sorts
      then
        ST
          {
              st_sort = s
            , st_lib_name = ln
            , st_node = n
            , st_branches = nexttraces
          }
      else
        SortNotFound

sortBeforeMorphism::Morphism a b c->SORT->SORT
sortBeforeMorphism m s =
  let
    maplist = Map.toList (sort_map m)
    previous_sort =
      case
        Data.List.find (\(a,b) -> b == s) maplist
      of
        Nothing -> s
        (Just (a,_)) -> a
  in
    previous_sort




buildAllSortTracesFor::
  LibEnv
  ->LIB_NAME
  ->Graph.Node
  ->[SortTrace]
buildAllSortTracesFor
  lenv
  ln
  n =
  let
    dg =
      devGraph
        $ Map.findWithDefault
          (error ((show ln) ++ ": no such Library in Environment!"))
          ln
          lenv
    node =
      fromMaybe
        (error ( (show n) ++ "No such node in DevGraph!") )
        (Graph.lab dg n)
    caslsign = getJustCASLSign $ getCASLSign (dgn_sign node)
    sorts = Set.toList $ sortSet caslsign
  in
    map
      (\s -> 
        buildSortTraceFor
          lenv
          ln
          []
          s
          n
      )
      sorts

instance Show [SortTrace] where
  show = concat . map (\st -> (show st) ++ "\n")



