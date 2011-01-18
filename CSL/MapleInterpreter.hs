{-# LANGUAGE  TypeSynonymInstances #-}
{- |
Module      :  $Header$
Description :  Maple instance for the AssignmentStore class
Copyright   :  (c) Ewaryst Schulz, DFKI Bremen 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Ewaryst.Schulz@dfki.de
Stability   :  experimental
Portability :  non-portable (via imports)

Maple as AssignmentStore
-}

module CSL.MapleInterpreter where

import Common.ProverTools (missingExecutableInPath)
import Common.Utils (getEnvDef, trimLeft)
import Common.DocUtils()
import Common.IOS
import Common.Result
import Common.ResultT

import CSL.AS_BASIC_CSL
import CSL.Parse_AS_Basic (parseResult)
import CSL.Interpreter
import CSL.Transformation
import CSL.Reduce_Interface (exportExp)

-- the process communication interface
import qualified Interfaces.Process as PC

import Control.Monad
import Control.Monad.Trans (MonadTrans (..), MonadIO (..))
import Control.Monad.State (MonadState (..))

import Data.List hiding (lookup)
import Data.Maybe
import System.Exit (ExitCode)

import Prelude hiding (lookup)

-- ----------------------------------------------------------------------
-- * Maple Calculator Instances
-- ----------------------------------------------------------------------

-- | MapleInterpreter with Translator based on the CommandState
data MITrans = MITrans { getBMap :: BMap
                       , getMI :: PC.CommandState }


-- Maple interface, built on CommandState
type MapleIO = ResultT (IOS MITrans)

instance AssignmentStore MapleIO where
    assign  = mapleAssign (evalMapleString False) mapleTransS mapleTransVarE
    assigns = mapleAssigns (evalMapleString False) mapleTransS mapleTransVarE
    lookup = mapleLookup (evalMapleString True) mapleTransS
    eval = mapleEval (evalMapleString True) mapleTransE
    check = mapleCheck (evalMapleString True) mapleTransE
    names = get >>= return . SMem . getBMap


-- ----------------------------------------------------------------------
-- * Maple Transformation Instances
-- ----------------------------------------------------------------------

-- | Variable generator instance for internal variables on the Hets-side,
-- in contrast to the newvar generation in lookupOrInsert of the BMap, which
-- generates variables for the Maple-side. We use nevertheless the same counter.
instance VarGen MapleIO where
    genVar = do
      s <- get
      let i = newkey $ getBMap s
      put $ s { getBMap = (getBMap s) { newkey = i + 1 } }
      return $ "?" ++ show i


-- ----------------------------------------------------------------------
-- * Maple syntax functions
-- ----------------------------------------------------------------------

cslMapleDefaultMapping :: [(OPNAME, String)]
cslMapleDefaultMapping = 
    let idmapping = map (\ x -> (x, show x))
--        ampmapping = map (\ x -> (x, "&" ++ show x))
        possibleIntervalOps = [ OP_mult, OP_div, OP_plus, OP_minus, OP_neg
                              , OP_cos,  OP_sin, OP_tan, OP_sqrt, OP_abs
                              , OP_neq, OP_lt, OP_leq, OP_eq, OP_gt, OP_geq ]
        logicOps = [ OP_and, OP_or, OP_impl ]
        otherOps = [ OP_factor, OP_maximize, OP_sign, OP_Pi, OP_min, OP_max
                   , OP_fthrt]
        specialOp = (OP_pow, "^")
--        specialOp = (OP_pow, "&**")
    in specialOp : idmapping logicOps
           ++ idmapping possibleIntervalOps
                  ++ idmapping otherOps

printAssignment :: String -> [String] -> EXPRESSION -> String
printAssignment n [] e = concat [n, ":= ", exportExp e, ";"]
printAssignment n l e = concat [n, ":= proc", args, exportExp e, " end proc;"]
    where args = concat [ "(", intercalate ", " l, ") " ]

printEvaluation :: EXPRESSION -> String
printEvaluation e = exportExp e ++ ";"

printLookup :: String -> String
printLookup n = n ++ ";"

-- | As maple does not evaluate boolean expressions we encode them in an
-- if-stmt and transform the numeric response back.
printBooleanExpr :: EXPRESSION -> String
printBooleanExpr e = concat [ "if evalf("
                            , exportExp e, ") then 1 else 0 fi;"
                            ]

getBooleanFromExpr :: EXPRESSION -> Bool
getBooleanFromExpr (Int 1 _) = True
getBooleanFromExpr (Int 0 _) = False
getBooleanFromExpr e =
    error $ "getBooleanFromExpr: can't translate expression to boolean: "
              ++ show e

-- ----------------------------------------------------------------------
-- * Generic Communication Interface
-- ----------------------------------------------------------------------

{- |
   The generic interface abstracts over the concrete evaluation function
-}

mapleAssign :: (AssignmentStore s, MonadResult s) => (String -> s [EXPRESSION])
          -> (ConstantName -> s String)
          -> ([String] -> EXPRESSION -> s (EXPRESSION, [String]))
          -> ConstantName -> AssDefinition -> s ()
mapleAssign ef trans transE n def = do
  let e = getDefiniens def
      args = getArguments def
  (e', args') <- transE args e
  n' <- trans n
  ef $ printAssignment n' args' e'
  return ()

mapleAssigns :: (AssignmentStore s, MonadResult s) => (String -> s [EXPRESSION])
          -> (ConstantName -> s String)
          -> ([String] -> EXPRESSION -> s (EXPRESSION, [String]))
          -> [(ConstantName, AssDefinition)] -> s ()
mapleAssigns ef trans transE l =
    let f (n, def) = do
          let e = getDefiniens def
              args = getArguments def
          (e', args') <- transE args e
          n' <- trans n
          return $ printAssignment n' args' e'
    in mapM f l >>= ef . unlines >> return ()

mapleLookup :: (AssignmentStore s, MonadResult s) => (String -> s [EXPRESSION])
           -> (ConstantName -> s String)
           -> ConstantName -> s (Maybe EXPRESSION)
mapleLookup ef trans n = do
  n' <- trans n
  el <- ef $ printLookup n'
  return $ listToMaybe el
-- we don't want to return nothing on id-lookup: "x; --> x"
--  if e == mkOp n [] then return Nothing else return $ Just e

mapleEval :: (AssignmentStore s, MonadResult s) => (String -> s [EXPRESSION])
        -> (EXPRESSION -> s EXPRESSION)
        -> EXPRESSION -> s EXPRESSION
mapleEval ef trans e = do
  e' <- trans e
  el <- ef $ printEvaluation e'
  if null el
   then error $ "mapleEval: expression " ++ show e' ++ " couldn't be evaluated"
   else return $ head el

mapleCheck :: (AssignmentStore s, MonadResult s) => (String -> s [EXPRESSION])
         -> (EXPRESSION -> s EXPRESSION)
         -> EXPRESSION -> s Bool
mapleCheck ef trans e = do
  e' <- trans e
  el <- ef $ printBooleanExpr e'
  if null el
   then error $ "mapleCheck: expression " ++ show e' ++ " couldn't be evaluated"
   else return $ getBooleanFromExpr $ head el


-- ----------------------------------------------------------------------
-- * The Communication Interface
-- ----------------------------------------------------------------------


wrapCommand :: IOS PC.CommandState a -> IOS MITrans a
wrapCommand ios = do
  r <- get
  let map' x = r { getMI = x }
  stmap map' getMI  ios

-- | A direct way to communicate with Maple
mapleDirect :: Bool -> MITrans -> String -> IO String
mapleDirect b rit s = do
  (res, _) <- runIOS (getMI rit) (PC.call 0.5 s)
  return $ if b then removeOutputComments res else res

mapleTransE :: EXPRESSION -> MapleIO EXPRESSION
mapleTransE e = do
  r <- get
  let bm = getBMap r
      (bm', e') = translateExpr bm e
  put r { getBMap = bm' }
  return e'

mapleTransVarE :: [String] -> EXPRESSION -> MapleIO (EXPRESSION, [String])
mapleTransVarE vl e = do
  r <- get
  let bm = getBMap r
      args = translateArgVars bm vl
      (bm', e') = translateExprWithVars vl bm e
  put r { getBMap = bm' }
  return (e', args)

mapleTransS :: ConstantName -> MapleIO String
mapleTransS s = do
  r <- get
  let bm = getBMap r
      (bm', s') = lookupOrInsert bm $ Left s
  --     outs = [ "lookingUp " ++ show s ++ " in "
  --            , show $ pretty bm, "{", show bm, "}" ]
  -- liftIO $ putStrLn $ unlines outs

  put r { getBMap = bm' }
  return s'


-- | Evaluate the given String as maple expression and eventually
-- parse the result to an expression list.
evalMapleString :: Bool -> String -> MapleIO [EXPRESSION]
evalMapleString b s = do
  -- 0.09 seconds is a critical value for the accepted response time of Maple
  res <- lift $ wrapCommand $ PC.call 0.7 s
  r <- get
  let bm = getBMap r
      trans = revtranslateExpr bm
  return $ if b then map trans $ maybeToList $ parseResult $ trimLeft
                      $ removeOutputComments res
           else []

-- | init the maple communication
mapleInit :: Int -- ^ Verbosity level
         -> IO MITrans
mapleInit v = do
  rc <- lookupMapleShellCmd
  libpath <- getEnvDef "HETS_MAPLELIB"
             $ error "mapleInit: Environment variable HETS_MAPLELIB not set."
  case rc of
    Left maplecmd -> do
            cs <- PC.start (maplecmd ++ " -q") v
                  $ Just PC.defaultConfig { PC.startTimeout = 3 }
            (_, cs') <- runIOS cs $ PC.call 1.0
                        $ concat [ "interface(prettyprint=0); Digits := 10;"
                                 , "libname := \"", libpath, "\", libname;"
                                 , "with(intpakX);with(intCompare);" ]
            return MITrans { getBMap = initWithDefault cslMapleDefaultMapping
                           , getMI = cs'
                           }
{-
-}

    _ -> error "Could not find maple shell command!"

mapleExit :: MITrans -> IO (Maybe ExitCode)
mapleExit mit = do
  (ec, _) <- runIOS (getMI mit) $ PC.close $ Just "quit;"
  return ec

execWithMaple :: MITrans -> MapleIO a -> IO (MITrans, a)
execWithMaple s m = do
  let err = error "execWithMaple: no result"
  (res, mit) <- runIOS s $ runResultT m
  return (mit, fromMaybe err $ maybeResult res)

runWithMaple :: Int -> MapleIO a -> IO (MITrans, a)
runWithMaple i m = mapleInit i >>= flip execWithMaple m

-- ----------------------------------------------------------------------
-- * The Maple system
-- ----------------------------------------------------------------------

-- | Left String is success, Right String is failure
lookupMapleShellCmd :: IO (Either String String)
lookupMapleShellCmd  = do
  cmd <- getEnvDef "HETS_MAPLE" "maple"
  -- check that prog exists
  noProg <- missingExecutableInPath cmd
  let f = if noProg then Right else Left
  return $ f cmd

-- | Removes lines starting with ">"
removeOutputComments :: String -> String
removeOutputComments s = 
    concat $ filter (\ x -> case x of '>' : _ -> False; _ -> True) $ lines s
 
{- Some problems with the maximization in Maple:

> Maximize(-x^6+t*x^3-3, {t >= -1000, t <= 1000}, x=-2..0);     
Error, (in Optimization:-NLPSolve) no improved point could be found
> Maximize(-x^t*x^3-3, {t >= -1000, t <= 1000}, x=-2..0);  
Error, (in Optimization:-NLPSolve) complex value encountered

-}
