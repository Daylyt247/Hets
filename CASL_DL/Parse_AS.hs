{-
Module      :  $Header$
Description :  Parser for CASL_DL
Copyright   :  (c) Klaus Luettich, Uni Bremen 2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

  Parser for CASL_DL logic
-}

module CASL_DL.Parse_AS where

import Common.AnnoState
import Common.Id
import Common.Lexer
import Common.Parsec
import Common.Token

import CASL_DL.AS_CASL_DL
import CASL.Formula
import CASL.AS_Basic_CASL

import Text.ParserCombinators.Parsec

dlFormula :: AParser st DL_FORMULA
dlFormula =
    try (
      do
       (ct,ctp) <- cardKeyword
       o <- oBracketT
       p <- parsePredSymb
       c <- cBracketT
       op <- oParenT
       t1 <- term casl_DL_reserved_words
       co <- anComma
       t2 <- term casl_DL_reserved_words
       cp <- cParenT
       return (Cardinality ct p t1 t2 Nothing
                   (appRange ctp (concatMapRange tokPos (o:c:op:co:[cp])))))
    <|>
     do
       (ct,ctp) <- cardKeyword
       o <- oBracketT
       p <- parsePredSymb
       c <- cBracketT
       op <- oParenT
       t1 <- term casl_DL_reserved_words
       co <- anComma
       t2 <- term casl_DL_reserved_words
       aco <- anComma
       t3 <- formula casl_DL_reserved_words
       cp <- cParenT
       return (Cardinality ct p t1 t2 (Just t3)
                   (appRange ctp (concatMapRange tokPos (o:c:op:co:aco:[cp]))))


parsePredSymb :: AParser st PRED_SYMB
parsePredSymb = fmap Pred_name (parseId casl_DL_reserved_words)
   <|>
   (do o <- oParenT << addAnnos
       Mixfix_qual_pred qpred <- qualPredName casl_DL_reserved_words o
       return qpred)
   <?> "a PRED_SYMB"

cardKeyword :: AParser st (CardType, Range)
cardKeyword = choice $ map ( \ v -> do
    kw <- asKey $ show v
    return (v, tokPos kw)) caslDLCardTypes

instance AParsable DL_FORMULA where
  aparser = dlFormula
