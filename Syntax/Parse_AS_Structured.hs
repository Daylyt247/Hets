
{- HetCATS/Syntax/Parse_AS_Structured.hs
   $Id$
   Author: Till Mossakowski, Christian Maeder
   Year:   2002/2003

   Parsing the Structured part of hetrogenous specifications.
   http://www.cofi.info/Documents/CASL/Summary/
   from 25 March 2001

   C.2.2 Structured Specifications

   todo:
    fixing of details concerning annos
    logic translations and implicit coercions
    "and" should do union of involved logics

    arch specs
-}

module Syntax.Parse_AS_Structured where

import Logic.Grothendieck
import Logic.Logic

import CASL.Logic_CASL  -- we need the default logic

import Syntax.AS_Structured
import Syntax.AS_Library
import Common.AS_Annotation
import Common.AnnoState
import Common.Id(tokPos)
import Common.Keywords
import Common.Lexer
import Common.Token
import Common.Lib.Parsec
import Common.Lib.Parsec.Char (digit)
import qualified Common.Lib.Map as Map
import Common.Id
import Data.List

import Data.Maybe(maybeToList)

import Syntax.Print_AS_Structured  -- for test purposes
import Syntax.Print_HetCASL

------------------------------------------------------------------------
-- annotation adapter
------------------------------------------------------------------------


annoParser2 parser = bind (\x (Annoted y pos l r) -> Annoted y pos (x++l) r) annos parser

emptyAnno :: a -> Annoted a
emptyAnno x = Annoted x [] [] []


------------------------------------------------------------------------
-- logic and encoding names
------------------------------------------------------------------------

-- exclude colon (because encoding must be recognized)
-- ecclude dot to recognize optional sublogic name

otherChars = "_`"
 
-- better list what is allowed rather than exclude what is forbidden
-- white spaces und non-printables should be not allowed!
encodingName = pToken(reserved (funS:casl_reserved_words) (many1 
		    (oneOf (otherChars ++ (signChars \\ ":.")) 
		     <|> scanLPD)))

-- keep these identical in order to
-- decide after seeing ".", ":" or "->" what was meant
logicName = do e <- encodingName
	       do string dotS
		  s <- encodingName
                  return (Logic_name e (Just s)) 
		 <|> return (Logic_name e Nothing)        

------------------------------------------------------------------------
-- parse Logic_code
------------------------------------------------------------------------

parseLogic :: AParser Logic_code
parseLogic = 
    do l <- asKey logicS
       do e <- logicName  -- try to parse encoding or logic source after "logic" 
          case e of 
		 Logic_name _ (Just _) -> parseOptLogTarget Nothing (Just e) [l]
		 Logic_name f Nothing -> 
		      do c <- asKey colonS
			 parseLogAfterColon (Just f) [l,c]
		      <|> parseOptLogTarget Nothing (Just e) [l]
         <|> do f <- asKey funS  -- parse at least a logic target after "logic"
		t <- logicName
		return (Logic_code Nothing Nothing (Just t) (map tokPos [l,f]))

-- parse optional logic source and target after a colon (given an encoding e)
parseLogAfterColon e l =
    do s <- logicName
       parseOptLogTarget e (Just s) l
	 <|> return (Logic_code e (Just s) Nothing (map tokPos l))
    <|> parseOptLogTarget e Nothing l
    <|> return (Logic_code e Nothing Nothing (map tokPos l))

-- parse an optional logic target (given encoding e or source s) 
parseOptLogTarget e s l =
    do f <- asKey funS
       do t <- logicName
	  return (Logic_code e s (Just t) (map tokPos (l++[f])))
        <|> return (Logic_code e s Nothing (map tokPos (l++[f])))

------------------------------------------------------------------------
-- for parsing "," not followed by "logic" within G_mapping
------------------------------------------------------------------------
-- ParsecCombinator.notFollowedBy only allows to check for a single "tok"
-- thus a single Char.

notFollowedWith :: GenParser tok st a -> GenParser tok st b 
		-> GenParser tok st a 

p1 `notFollowedWith` p2 = try ((p1 >> p2 >> pzero) <|> p1)

plainComma = anComma `notFollowedWith` asKey logicS

-- rearrange list to keep current logic as first element
-- does not consume anything! (may only fail)
{-switchLogic :: Logic_code -> LogicGraph -> GenParser Char st LogicGraph
switchLogic n l@(Logic i : _) =
       let s = case n of 
	       Logic_code _ _ (Just (Logic_name t _)) _ -> tokStr t
	       _ -> language_name i
	   (f, r) =  partition (\ (Logic x) -> language_name x == s) l
       in if null f then fail ("unknown language " ++ s)
	  else return (f++r)
-}

------------------------------------------------------------------------
-- parse G_mapping (if you modify this, do so for G_hiding, too!)
------------------------------------------------------------------------

parseItemsMap :: AnyLogic -> AParser (G_symb_map_items_list, [Token])
parseItemsMap (Logic lid) = 
   do (cs, ps) <- callParser (parse_symb_map_items lid) (language_name lid) "symbol maps"
                      `separatedBy` anComma 
            -- ??? should be plainComma, but does not work for reveal s,t!
      return (G_symb_map_items_list lid cs, ps)


parseMapping :: (AnyLogic, LogicGraph) -> AParser ([G_mapping], [Token])
parseMapping l =
    do n <- parseLogic
       do c <- anComma
	  (gs, ps) <- parseMapping l
	  return (G_logic_translation n : gs, c:ps)
        <|> return ([G_logic_translation n], [])
    <|> do (m, ps) <- parseItemsMap $ fst l
	   do  c <- anComma 
  	       (gs, qs) <- parseMapping l
	       return (G_symb_map m : gs, ps ++ c : qs)
	     <|> return ([G_symb_map m], ps)

------------------------------------------------------------------------
-- parse G_hiding (copied from above, but code sharing would be better!) 
------------------------------------------------------------------------

parseItemsList :: (AnyLogic, LogicGraph) -> AParser (G_symb_items_list, [Token])
parseItemsList l@(Logic lid, _) = 
   do (cs, ps) <- callParser (parse_symb_items lid) (language_name lid) "symbols"
                      `separatedBy` plainComma
      return (G_symb_items_list lid cs, []) 


parseHiding :: (AnyLogic, LogicGraph) -> AParser ([G_hiding], [Token])
parseHiding l =
    do n <- parseLogic
       do c <- anComma
	  (gs, ps) <- parseHiding l
	  return (G_logic_projection n : gs, c:ps)
        <|> return ([G_logic_projection n], [])
    <|> do (m, ps) <- parseItemsList l
	   do  c <- anComma 
  	       (gs, qs) <- parseHiding l
	       return (G_symb_list m : gs, ps ++ c : qs)
	     <|> return ([G_symb_list m], ps)

parseRevealing :: (AnyLogic, LogicGraph) -> AParser (G_symb_map_items_list, [Token])
parseRevealing l = error "Parse_AS_Structured.hs:parseRevealing"

------------------------------------------------------------------------
-- specs
------------------------------------------------------------------------

spec :: (AnyLogic, LogicGraph) -> AParser (Annoted SPEC)
spec l = do (sps,ps) <- annoParser2 (specA l) `separatedBy` (asKey thenS)
            return (case sps of
                    [sp] -> sp
                    otherwise -> emptyAnno (Extension sps (map tokPos ps)))

specA :: (AnyLogic, LogicGraph) -> AParser (Annoted SPEC)
specA l = do (sps,ps) <- annoParser (specB l) `separatedBy` (asKey andS)
             return (case sps of
                     [sp] -> sp
                     otherwise -> emptyAnno (Union sps (map tokPos ps)))

specB :: (AnyLogic, LogicGraph) -> AParser SPEC
specB l = do p1 <- asKey localS
             sp1 <- aSpec l
             p2 <- asKey withinS
             sp2 <- annoParser (specB l)
             return (Local_spec sp1 sp2 (map tokPos [p1,p2]))
          <|> do sp <- specC l
                 return (item sp) -- ??? what to do with anno?

specC :: (AnyLogic, LogicGraph) -> AParser (Annoted SPEC)
specC l@(Logic lid, lG) =     
              do p1 <- asKey "data"
                 case data_logic lid of
                   Nothing -> fail ("No data logic for " ++ language_name lid)
                   Just (Logic dlid) -> do
                     sp1 <- groupSpec (Logic dlid, lG)
                     sp2 <- specD l
                     return (emptyAnno (Data (Logic dlid) 
                                             (emptyAnno sp1) 
                                             (emptyAnno sp2) 
                                             [tokPos p1]))
          <|> do sp <- annoParser (specD l)
                 translation_list l sp
          
translation_list l sp =
     do sp' <- translation l sp
        translation_list l sp'
 <|> return sp

translation l sp =
     do p <- asKey withS
        (m, ps) <- parseMapping l
        return (emptyAnno (Translation sp (Renaming m (map tokPos (p:ps)))))
 <|> do p <- asKey hideS
        (m, ps) <- parseHiding l
        return (emptyAnno (Reduction sp (Hidden m (map tokPos (p:ps)))))
 <|> do p <- asKey revealS
        (m, ps) <- parseItemsMap $ fst l
        return (emptyAnno (Reduction sp (Revealed m (map tokPos (p:ps)))))

specD :: (AnyLogic, LogicGraph) -> AParser SPEC
           -- do some lookahead for free spec, to avoid clash with free type
specD l = do (p,sp) <- try (do p <- asKey freeS
                               sp <- groupSpec l
                               return (p,sp))
	     return (Free_spec (emptyAnno sp) [tokPos p])
      <|> do (p,sp) <- try (do p <- asKey cofreeS
                               sp <- groupSpec l
                               return (p,sp))
             return (Cofree_spec (emptyAnno sp) [tokPos p])
      <|> do p <- asKey closedS
             sp <- groupSpec l
             return (Closed_spec (emptyAnno sp) [tokPos p])
      <|> specE l
       
specE :: (AnyLogic, LogicGraph) -> AParser SPEC
specE l = do lookAhead (try (oBraceT >> cBraceT)) -- avoid overlap with group spec
             basicSpec l        
      <|> do lookAhead (oBraceT <|> ((simpleId << annos) 
				     `followedWith`
				     (asKey withS <|> asKey hideS
				      <|> asKey revealS <|> asKey andS
				      <|> asKey thenS <|> cBraceT
				      <|> asKey fitS
				      <|> asKey withinS <|> asKey endS
				      <|> oBracketT <|> cBracketT
				      <|> (eof >> return (Token "" nullPos)))
				    ))
	     groupSpec l
      <|> logicSpec l
      <|> basicSpec l



callParser p name itemType = do
    s <- getInput
    pos <- getPosition
    (x,rest,pos') <- case p of 
	 Nothing -> fail ("no "++itemType++" parser for language " 
			    ++ name)
	 Just pa -> return (pa pos s)
    setInput rest
    setPosition pos'
    return x


basicSpec :: (AnyLogic, LogicGraph) -> AParser SPEC
basicSpec l@(Logic lid, _) = 
              do bspec <- callParser (parse_basic_spec lid) (language_name lid)
                            "basic specification"
                 return (Basic_spec (G_basic_spec lid bspec))


logicSpec :: (AnyLogic, LogicGraph) -> AParser SPEC
logicSpec (oldlog, lG) = do
   s1 <- asKey logicS
   log <- logicName
   let Logic_name t _ = log
   s2 <- asKey ":"
   let newlog = lookupLogicName log lG
       logtrans = coercelog newlog oldlog
   sp <- annoParser (specE (newlog, lG))
   let sp1 = Qualified_spec log sp (map tokPos [s1,t,s2])
   return (logtrans sp1)

lookupLogicName :: Logic_name -> LogicGraph -> AnyLogic
lookupLogicName (Logic_name log sublog) lg = 
    lookupLogic "Parser: " (tokStr log) lg

{- a code snippit to lookup the sublogic:
      case sublog of
        Nothing -> Logic lid
        Just s ->
         case find (\sub -> tokStr s `elem` sublogic_names lid sub) 
                   (all_sublogics lid) of
            Nothing -> error ("sublogic "++tokStr s++
                              " in logic "++tokStr log++" unknown")
            Just sub -> Logic lid  -- ??? can we throw away sublogic?
-}
coercelog (Logic newlid) (Logic oldlid) =
  if newlang == oldlang then id
   else error ("Cannot coerce from "++newlang++" to "++oldlang)
  where newlang = language_name newlid
        oldlang = language_name oldlid
   -- \sp -> Translation (emptyAnno sp) (Renaming [G_logic_translation (Logic_code...)] [])

aSpec l = annoParser2 (spec l)

groupSpec l = do b <- oBraceT
		 a <- aSpec l
		 c <- cBraceT
		 return (Group a (map tokPos [b, c])) 
	      <|>
	      do n <- simpleId
		 (f,ps) <- fitArgs l
		 return (Spec_inst n f ps)

fitArgs :: (AnyLogic, LogicGraph) -> AParser ([Annoted FIT_ARG],[Pos])
fitArgs l = do fas <- many (fitArg l)
               let (fas1,ps) = unzip fas
               return (fas1,concat ps)

fitArg :: (AnyLogic, LogicGraph) -> AParser (Annoted FIT_ARG,[Pos])
fitArg l = do b <- oBracketT   
              fa <- annoParser (fittingArg l)
              c <- cBracketT
              return (fa,[tokPos b,tokPos c])

fittingArg :: (AnyLogic, LogicGraph) -> AParser FIT_ARG
fittingArg l@(Logic lid, _) = 
               do (an,s) <- try (do an <- annos
                                    s <- asKey viewS
                                    return (an,s))
                  vn <- simpleId
                  (fa,ps) <- fitArgs l
                  return (Fit_view vn fa (tokPos s:ps) an)
            <|>
               do sp <- aSpec l
                  (symbit,ps) <- option (G_symb_map_items_list lid [],[]) 
                                 (do s <- asKey fitS               
                                     (m, ps) <- parseItemsMap $ fst l
                                     return (m,[tokPos s]))
                  return (Fit_spec sp symbit ps)


optEnd = option Nothing (fmap Just (asKey endS))
       
generics l = do 
   (pa,ps1) <- params l
   (imp,ps2) <- option ([],[]) (imports l)
   return (Genericity (Params pa) (Imported imp) (ps1++ps2))

params :: (AnyLogic, LogicGraph) -> AParser ([Annoted SPEC],[Pos])
params l = do pas <- many (param l)
              let (pas1,ps) = unzip pas
              return (pas1,concat ps)

param :: (AnyLogic, LogicGraph) -> AParser (Annoted SPEC,[Pos])
param l = do b <- oBracketT   
             pa <- aSpec l
             c <- cBracketT
             return (pa,[tokPos b,tokPos c])

imports l = do s <- asKey givenS
               (sps,ps) <- annoParser (groupSpec l) `separatedBy` anComma
               return (sps,map tokPos (s:ps))

libItem l@(log, lG) = -- spec defn
    do s <- asKey specS 
       n <- simpleId
       g <- generics l
       e <- asKey equalS
       a <- aSpec l
       q <- optEnd
       return (Syntax.AS_Library.Spec_defn n g a 
	       (map tokPos ([s, e] ++ maybeToList q)), log)
  <|> -- view defn
    do s1 <- asKey viewS
       vn <- simpleId
       g <- generics l
       s2 <- asKey ":"
       vt <- viewType l
       (symbMap,ps) <- option ([],[]) 
                        (do s <- asKey equalS               
                            (m, ps) <- parseMapping l
                            return (m,[s]))          
       q <- optEnd
       return (Syntax.AS_Library.View_defn vn g vt symbMap 
                    (map tokPos ([s1,s2] ++ ps ++ maybeToList q)), log)
  <|> -- download
    do s1 <- asKey fromS
       ln <- libName
       s2 <- asKey getS
       (il,ps) <- itemNameOrMap `separatedBy` anComma
       q <- optEnd
       return (Download_items ln il 
                (map tokPos ([s1,s2]++ps++ maybeToList q)), log)
  <|> -- logic
    do s1 <- asKey logicS
       logN <- logicName
       let Logic_name t _ = logN
       return (Logic_decl logN (map tokPos [s1,t]),
	      lookupLogicName logN lG)

viewType l = do sp1 <- annoParser (groupSpec l)
                s <- asKey toS
                sp2 <- annoParser (groupSpec l)
                return (View_type sp1 sp2 [tokPos s])

libName = do libid <- libId
             v <- option Nothing (fmap Just version)
             return (case v of
               Nothing -> Lib_id libid
               Just v1 -> Lib_version libid v1)

libId = do pos <- getPosition
           path <- scanAnyWords `sepBy1` (string "/")
           skip
           return (Indirect_link (concat (intersperse "/" path)) [pos])
           -- ??? URL need to be added

version = do s <- asKey versionS
             pos <- getPosition
             n <- many1 digit `sepBy1` (string ".")
             skip
             return (Version_number n ([tokPos s, pos]))

itemNameOrMap = do i1 <- simpleId
                   i' <- option Nothing (do
                      s <- asKey "|->"
                      i <- simpleId
                      return (Just (i,s)))
                   return (case i' of
                      Nothing -> Item_name i1
                      Just (i2,s) -> Item_name_map i1 i2 [tokPos s])

libItems :: (AnyLogic, LogicGraph) -> AParser [Annoted LIB_ITEM]
libItems l@(_, lG) = option [] $ do 
    (r, newlog) <- libItem l
    an <- annos 
    is <- libItems (newlog, lG)
    return ((Annoted r [] [] an) : is)

library l = do s1 <- asKey libraryS
               ln <- libName
               an <- annos
               ls <- libItems l
               eof
               return (Lib_defn ln ls [tokPos s1] an)
               
