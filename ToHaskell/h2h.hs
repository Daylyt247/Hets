{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  experimental
Portability :  portable 
   
test translation
-}

module Main where

import System.Environment

import Text.ParserCombinators.Parsec
import Common.Result
import Common.AnnoState
import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.PrettyPrint

import ToHaskell.FromHasCASL

import Haskell.HatAna

import HasCASL.Le
import HasCASL.AsToLe
import HasCASL.ParseItem(basicSpec)
import HasCASL.ProgEq

hParser :: AParser () (Sign, [Named (TiDecl PNT)])
hParser = do 
   b <- basicSpec
   let res@(Result _ m) = do 
          (_, _, sig, sens) <- basicAnalysis(b, initialEnv, emptyGlobalAnnos)
          mapTheory (sig, map (mapNamed $ translateSen sig) sens)
   case m of 
      Nothing -> error $ show res
      Just x -> return x

main :: IO ()
main = do l <- getArgs
	  if length l >= 1 then
	     do s <- readFile $ head l
		let r = runParser hParser (emptyAnnos ()) (head l) s 
	        case r of 
		       Right (sig, hs) -> do
		           putStrLn $ showPretty sig ""
			   mapM_ (putStrLn . flip showPretty "") hs
		       Left err -> putStrLn $ show err
	     else putStrLn "missing argument"
