{-
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, Wiebke Herding, C. Maeder, Uni Bremen 2004
Licence     :  All rights reserved.

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

  Parser for modal logic extension of CASL
-}

module Modal.Parse_AS where

import Common.AnnoState
import Common.Id
import Common.Keywords
import Common.Lexer
import Common.Token
import Modal.AS_Modal
import Common.Lib.Parsec
import CASL.Formula
import CASL.OpItem

modalFormula :: AParser M_FORMULA
modalFormula = 
    do o <- oBracketT
       m <- modality []
       c <- cBracketT
       f <- formula modal_reserved_words
       return (Box m f $ toPos o [] c)
    <|> 
    do o <- asKey lessS
       m <- modality [greaterS] -- do not consume matching ">"!
       c <- asKey greaterS
       f <- formula modal_reserved_words
       return (Diamond m f $ toPos o [] c)
    <|> 
    do d <- asKey diamondS
       f <- formula modal_reserved_words
       let p = tokPos d
       return (Diamond (Simple_mod $ Token emptyS p) f [p])

modality :: [String] -> AParser MODALITY
modality ks = 
    do t <- term (ks ++ modal_reserved_words)
       return $ Term_mod t
   <|> return (Simple_mod $ mkSimpleId emptyS)

instance AParsable M_FORMULA where
  aparser = modalFormula

rigor :: AParser RIGOR
rigor = (asKey rigidS >> return Rigid) 
	<|> (asKey flexibleS >> return Flexible)

rigidSigItems :: AParser M_SIG_ITEM
rigidSigItems = 
    do r <- rigor
       do itemList modal_reserved_words opS opItem (Rigid_op_items r)
	 <|> itemList modal_reserved_words predS predItem (Rigid_pred_items r)

instance AParsable M_SIG_ITEM where
  aparser = rigidSigItems

mKey :: AParser Token
mKey = asKey modalityS <|> asKey modalityS

mBasic :: AParser M_BASIC_ITEM
mBasic = 
    do c <- mKey
       auxItemList (modal_reserved_words ++ startKeyword)
		       [c] simpleId Simple_mod_decl
    <|>
    do t <- asKey termS
       c <- mKey
       auxItemList (modal_reserved_words ++ startKeyword) 
		       [t, c] (sortId modal_reserved_words) Term_mod_decl
		
instance AParsable M_BASIC_ITEM where
  aparser = mBasic
