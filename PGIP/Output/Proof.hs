{-# LANGUAGE CPP
           , DeriveGeneric
           , TemplateHaskell
           , EmptyDataDecls
           , TypeFamilies
           , DeriveDataTypeable
           #-}

module PGIP.Output.Proof
  ( ProofFormatterOptions
  , proofFormatterOptions
  , pfoIncludeProof
  , pfoIncludeDetails

  , ProofResult
  , formatProofs
  ) where

import PGIP.Output.Mime

import Interfaces.GenericATPState (tsTimeLimit, tsExtraOpts)

import qualified Logic.Prover as LP

import Proofs.AbstractState (G_proof_tree)

import Common.Json (ppJson, asJson)

import Data.Data
import Data.Time.LocalTime

import Numeric

type ProofResult = (String, String, String, Maybe (LP.ProofStatus G_proof_tree))
type ProofFormatter = ProofFormatterOptions -> [(String, [ProofResult])] -> (String, String)
                                            -- ^[(dgNodeName, result)]      ^(responseType, response)

data ProofFormatterOptions = ProofFormatterOptions
  { pfoIncludeProof :: Bool
  , pfoIncludeDetails :: Bool
  } deriving (Show, Eq)

proofFormatterOptions :: ProofFormatterOptions
proofFormatterOptions = ProofFormatterOptions
  { pfoIncludeProof = True
  , pfoIncludeDetails = True
  }

formatProofs :: Maybe String -> ProofFormatter
formatProofs format options proofs = case format of
  Just "json" -> formatAsJSON
  _ -> formatAsXML
  where
  proof = map convertProof proofs
  formatAsJSON :: (String, String)
  formatAsJSON = (jsonC, ppJson $ asJson proof)

  formatAsXML :: (String, String)
  formatAsXML = (xmlC, undefined proof)

  convertProof :: (String, [ProofResult]) -> Proof
  convertProof (nodeName, proofResults) = Proof
    { node = nodeName
    , goals = map convertGoal proofResults
    }

  convertGoal :: ProofResult -> ProofGoal
  convertGoal (goalName, goalResult, goalDetails, proofStatusM) = ProofGoal
    { name = goalName
    , result = goalResult
    , details =
        if pfoIncludeDetails options
        then Just goalDetails
        else Nothing
    , usedProver = fmap LP.usedProver proofStatusM
    , tacticScript = fmap convertTacticScript proofStatusM
    , proofTree = fmap (show . LP.proofTree) proofStatusM
    , usedTime = fmap (convertTime . LP.usedTime) proofStatusM
    , usedAxioms = fmap LP.usedAxioms proofStatusM
    , proverOutput =
        if pfoIncludeProof options
        then fmap (unlines . LP.proofLines) proofStatusM
        else Nothing
    }

  convertTime :: TimeOfDay -> ProofTime
  convertTime tod = ProofTime
    { seconds = read $ init $ show $ timeOfDayToTime tod
    , components = convertTimeComponents tod
    }

  convertTimeComponents :: TimeOfDay -> ProofTimeComponents
  convertTimeComponents tod = ProofTimeComponents
    { hours = todHour tod
    , mins = todMin tod
    , secs = case readSigned readFloat $ show $ todSec tod of
        [(n, "")] -> n
        _ -> error $ "Failed reading the number " ++ show (todSec tod)
    }

  convertTacticScript :: LP.ProofStatus G_proof_tree -> TacticScript
  convertTacticScript ps =
    let atp = read $ (\(LP.TacticScript ts) -> ts) $ LP.tacticScript ps
    in TacticScript { timeLimit = tsTimeLimit atp
                    , extraOptions = tsExtraOpts atp
                    }

data Proof = Proof
  { node :: String
  , goals :: [ProofGoal]
  } deriving (Show, Typeable, Data)

data ProofGoal = ProofGoal
  { name :: String
  , result :: String
  , details :: Maybe String
  , usedProver :: Maybe String
  , tacticScript :: Maybe TacticScript
  , proofTree :: Maybe String
  , usedTime :: Maybe ProofTime
  , usedAxioms :: Maybe [String]
  , proverOutput :: Maybe String
  } deriving (Show, Typeable, Data)

data TacticScript = TacticScript
  { timeLimit :: Int
  , extraOptions :: [String]
  } deriving (Show, Typeable, Data)

data ProofTime = ProofTime
  { seconds :: Int
  , components :: ProofTimeComponents
  } deriving (Show, Typeable, Data)

data ProofTimeComponents = ProofTimeComponents
  { hours :: Int
  , mins :: Int
  , secs :: Double
  } deriving (Show, Typeable, Data)
