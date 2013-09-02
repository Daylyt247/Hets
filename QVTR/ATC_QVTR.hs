{-# OPTIONS -w -O0 #-}
{-# LANGUAGE StandaloneDeriving, DeriveDataTypeable #-}
{- |
Module      :  QVTR/ATC_QVTR.der.hs
Description :  generated Typeable, ShATermConvertible instances
Copyright   :  (c) DFKI GmbH 2012
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable(derive Typeable instances)

Automatic derivation of instances via DrIFT-rule Typeable, ShATermConvertible
  for the type(s):
'QVTR.As.Transformation'
'QVTR.As.Key'
'QVTR.As.PropKey'
'QVTR.As.Relation'
'QVTR.As.RelVar'
'QVTR.As.PrimitiveDomain'
'QVTR.As.Domain'
'QVTR.As.ObjectTemplate'
'QVTR.As.PropertyTemplate'
'QVTR.As.WhenWhere'
'QVTR.As.RelInvok'
'QVTR.Sign.RuleDef'
'QVTR.Sign.Sign'
'QVTR.Sign.Sen'
-}

{-
Generated by 'genRules' (automatic rule generation for DrIFT). Don't touch!!
  dependency files:
QVTR/As.hs
QVTR/Sign.hs
-}

module QVTR.ATC_QVTR () where

import CSMOF.ATC_CSMOF

import ATerm.Lib
import CSMOF.Print ()
import Common.ATerm.ConvInstances
import Common.Doc
import Common.DocUtils
import Common.Id
import Data.Typeable
import QVTR.As
import QVTR.Print ()
import QVTR.Sign
import qualified CSMOF.As as CSMOF
import qualified CSMOF.Sign as CSMOF
import qualified Data.Map as Map

{-! for QVTR.As.Transformation derive : Typeable !-}
{-! for QVTR.As.Key derive : Typeable !-}
{-! for QVTR.As.PropKey derive : Typeable !-}
{-! for QVTR.As.Relation derive : Typeable !-}
{-! for QVTR.As.RelVar derive : Typeable !-}
{-! for QVTR.As.PrimitiveDomain derive : Typeable !-}
{-! for QVTR.As.Domain derive : Typeable !-}
{-! for QVTR.As.ObjectTemplate derive : Typeable !-}
{-! for QVTR.As.PropertyTemplate derive : Typeable !-}
{-! for QVTR.As.WhenWhere derive : Typeable !-}
{-! for QVTR.As.RelInvok derive : Typeable !-}
{-! for QVTR.Sign.RuleDef derive : Typeable !-}
{-! for QVTR.Sign.Sign derive : Typeable !-}
{-! for QVTR.Sign.Sen derive : Typeable !-}

{-! for QVTR.As.Transformation derive : ShATermConvertible !-}
{-! for QVTR.As.Key derive : ShATermConvertible !-}
{-! for QVTR.As.PropKey derive : ShATermConvertible !-}
{-! for QVTR.As.Relation derive : ShATermConvertible !-}
{-! for QVTR.As.RelVar derive : ShATermConvertible !-}
{-! for QVTR.As.PrimitiveDomain derive : ShATermConvertible !-}
{-! for QVTR.As.Domain derive : ShATermConvertible !-}
{-! for QVTR.As.ObjectTemplate derive : ShATermConvertible !-}
{-! for QVTR.As.PropertyTemplate derive : ShATermConvertible !-}
{-! for QVTR.As.WhenWhere derive : ShATermConvertible !-}
{-! for QVTR.As.RelInvok derive : ShATermConvertible !-}
{-! for QVTR.Sign.RuleDef derive : ShATermConvertible !-}
{-! for QVTR.Sign.Sign derive : ShATermConvertible !-}
{-! for QVTR.Sign.Sen derive : ShATermConvertible !-}

-- Generated by DrIFT, look but don't touch!

instance ShATermConvertible RelInvok where
  toShATermAux att0 xv = case xv of
    RelInvok a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "RelInvok" [a', b'] []) att2
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "RelInvok" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, RelInvok a' b') }}
    u -> fromShATermError "RelInvok" u

instance ShATermConvertible WhenWhere where
  toShATermAux att0 xv = case xv of
    When a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "When" [a', b'] []) att2
    Where a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "Where" [a', b'] []) att2
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "When" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, When a' b') }}
    ShAAppl "Where" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, Where a' b') }}
    u -> fromShATermError "WhenWhere" u

instance ShATermConvertible PropertyTemplate where
  toShATermAux att0 xv = case xv of
    PropertyTemplate a b c -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      return $ addATerm (ShAAppl "PropertyTemplate" [a', b', c'] []) att3
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "PropertyTemplate" [a, b, c] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      (att3, PropertyTemplate a' b' c') }}}
    u -> fromShATermError "PropertyTemplate" u

instance ShATermConvertible ObjectTemplate where
  toShATermAux att0 xv = case xv of
    ObjectTemplate a b c d -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      (att4, d') <- toShATerm' att3 d
      return $ addATerm (ShAAppl "ObjectTemplate" [a', b', c',
                                                   d'] []) att4
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "ObjectTemplate" [a, b, c, d] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      case fromShATerm' d att3 of
      { (att4, d') ->
      (att4, ObjectTemplate a' b' c' d') }}}}
    u -> fromShATermError "ObjectTemplate" u

instance ShATermConvertible Domain where
  toShATermAux att0 xv = case xv of
    Domain a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "Domain" [a', b'] []) att2
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "Domain" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, Domain a' b') }}
    u -> fromShATermError "Domain" u

instance ShATermConvertible PrimitiveDomain where
  toShATermAux att0 xv = case xv of
    PrimitiveDomain a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "PrimitiveDomain" [a', b'] []) att2
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "PrimitiveDomain" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, PrimitiveDomain a' b') }}
    u -> fromShATermError "PrimitiveDomain" u

instance ShATermConvertible RelVar where
  toShATermAux att0 xv = case xv of
    RelVar a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "RelVar" [a', b'] []) att2
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "RelVar" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, RelVar a' b') }}
    u -> fromShATermError "RelVar" u

instance ShATermConvertible Relation where
  toShATermAux att0 xv = case xv of
    Relation a b c d e f g h -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      (att4, d') <- toShATerm' att3 d
      (att5, e') <- toShATerm' att4 e
      (att6, f') <- toShATerm' att5 f
      (att7, g') <- toShATerm' att6 g
      (att8, h') <- toShATerm' att7 h
      return $ addATerm (ShAAppl "Relation" [a', b', c', d', e', f', g',
                                             h'] []) att8
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "Relation" [a, b, c, d, e, f, g, h] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      case fromShATerm' d att3 of
      { (att4, d') ->
      case fromShATerm' e att4 of
      { (att5, e') ->
      case fromShATerm' f att5 of
      { (att6, f') ->
      case fromShATerm' g att6 of
      { (att7, g') ->
      case fromShATerm' h att7 of
      { (att8, h') ->
      (att8, Relation a' b' c' d' e' f' g' h') }}}}}}}}
    u -> fromShATermError "Relation" u

instance ShATermConvertible PropKey where
  toShATermAux att0 xv = case xv of
    SimpleProp a -> do
      (att1, a') <- toShATerm' att0 a
      return $ addATerm (ShAAppl "SimpleProp" [a'] []) att1
    OppositeProp a b -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      return $ addATerm (ShAAppl "OppositeProp" [a', b'] []) att2
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "SimpleProp" [a] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      (att1, SimpleProp a') }
    ShAAppl "OppositeProp" [a, b] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      (att2, OppositeProp a' b') }}
    u -> fromShATermError "PropKey" u

instance ShATermConvertible Key where
  toShATermAux att0 xv = case xv of
    Key a b c -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      return $ addATerm (ShAAppl "Key" [a', b', c'] []) att3
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "Key" [a, b, c] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      (att3, Key a' b' c') }}}
    u -> fromShATermError "Key" u

instance ShATermConvertible Transformation where
  toShATermAux att0 xv = case xv of
    Transformation a b c d e -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      (att4, d') <- toShATerm' att3 d
      (att5, e') <- toShATerm' att4 e
      return $ addATerm (ShAAppl "Transformation" [a', b', c', d',
                                                   e'] []) att5
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "Transformation" [a, b, c, d, e] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      case fromShATerm' d att3 of
      { (att4, d') ->
      case fromShATerm' e att4 of
      { (att5, e') ->
      (att5, Transformation a' b' c' d' e') }}}}}
    u -> fromShATermError "Transformation" u

deriving instance Typeable RelInvok

deriving instance Typeable WhenWhere

deriving instance Typeable PropertyTemplate

deriving instance Typeable ObjectTemplate

deriving instance Typeable Domain

deriving instance Typeable PrimitiveDomain

deriving instance Typeable RelVar

deriving instance Typeable Relation

deriving instance Typeable PropKey

deriving instance Typeable Key

deriving instance Typeable Transformation

instance ShATermConvertible Sen where
  toShATermAux att0 xv = case xv of
    KeyConstr a -> do
      (att1, a') <- toShATerm' att0 a
      return $ addATerm (ShAAppl "KeyConstr" [a'] []) att1
    QVTSen a -> do
      (att1, a') <- toShATerm' att0 a
      return $ addATerm (ShAAppl "QVTSen" [a'] []) att1
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "KeyConstr" [a] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      (att1, KeyConstr a') }
    ShAAppl "QVTSen" [a] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      (att1, QVTSen a') }
    u -> fromShATermError "Sen" u

instance ShATermConvertible Sign where
  toShATermAux att0 xv = case xv of
    Sign a b c d e -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      (att4, d') <- toShATerm' att3 d
      (att5, e') <- toShATerm' att4 e
      return $ addATerm (ShAAppl "Sign" [a', b', c', d', e'] []) att5
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "Sign" [a, b, c, d, e] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      case fromShATerm' d att3 of
      { (att4, d') ->
      case fromShATerm' e att4 of
      { (att5, e') ->
      (att5, Sign a' b' c' d' e') }}}}}
    u -> fromShATermError "Sign" u

instance ShATermConvertible RuleDef where
  toShATermAux att0 xv = case xv of
    RuleDef a b c -> do
      (att1, a') <- toShATerm' att0 a
      (att2, b') <- toShATerm' att1 b
      (att3, c') <- toShATerm' att2 c
      return $ addATerm (ShAAppl "RuleDef" [a', b', c'] []) att3
  fromShATermAux ix att0 = case getShATerm ix att0 of
    ShAAppl "RuleDef" [a, b, c] _ ->
      case fromShATerm' a att0 of
      { (att1, a') ->
      case fromShATerm' b att1 of
      { (att2, b') ->
      case fromShATerm' c att2 of
      { (att3, c') ->
      (att3, RuleDef a' b' c') }}}
    u -> fromShATermError "RuleDef" u

deriving instance Typeable Sen

deriving instance Typeable Sign

deriving instance Typeable RuleDef
