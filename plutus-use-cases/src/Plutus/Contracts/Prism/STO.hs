{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE MonoLocalBinds     #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE TemplateHaskell    #-}
{-# LANGUAGE TypeApplications   #-}
{-# LANGUAGE TypeOperators      #-}
{-

This module defines an STO that allocates coins to anyone who

* Presents a specific credential token (one that has been issued by a specific
  credential authority with a specific name) and
* Pays 1 Lovelace to a predefined public key address for every coin minted

The supply (number of tokens created) of the STO is unlimited. This is done so
that we do not need a state machine and can participate in the STO with a single
transaction. In a more realistic setting we would also need constraints on the
validity range of the minting transaction.

-}
module Plutus.Contracts.Prism.STO(
    STOData(..)
    , policy
    , coins
    ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Ledger.Ada (Ada (..), fromValue)
import Ledger.Contexts (ScriptContext (..), ScriptPurpose (..))
import Ledger.Contexts qualified as Validation
import Ledger.Crypto (PubKeyHash)
import Ledger.Scripts (MintingPolicy, mintingPolicyHash, mkMintingPolicyScript)
import Ledger.Typed.Scripts qualified as Scripts
import Ledger.Value (TokenName, Value)
import Ledger.Value qualified as Value
import PlutusTx qualified
import PlutusTx.Prelude
import Prelude qualified as Haskell

data STOData =
    STOData
        { stoIssuer          :: PubKeyHash
        , stoTokenName       :: TokenName
        , stoCredentialToken :: Value
        }
    deriving stock (Generic, Haskell.Eq, Haskell.Show)
    deriving anyclass (ToJSON, FromJSON)

{-# INLINABLE validateSTO #-}
validateSTO :: STOData -> () -> ScriptContext -> Bool
validateSTO STOData{stoIssuer,stoCredentialToken,stoTokenName} _ ScriptContext{scriptContextTxInfo=txInfo,scriptContextPurpose=Minting ownHash} =
    let tokenOK = stoCredentialToken `Value.leq` Validation.valueSpent txInfo
        Lovelace paidToIssuer = fromValue (Validation.valuePaidTo txInfo stoIssuer)
        mintOK =
            -- Note that this doesn't prevent any tokens with a name other than
            -- 'stoTokenName' from being minted
            Value.valueOf (Validation.txInfoMint txInfo) ownHash stoTokenName == paidToIssuer
    in tokenOK && mintOK
validateSTO _ _ _ = error ()

policy :: STOData -> MintingPolicy
policy stoData = mkMintingPolicyScript $
    $$(PlutusTx.compile [|| \c -> Scripts.wrapMintingPolicy (validateSTO c) ||]) `PlutusTx.applyCode` PlutusTx.liftCode stoData

-- | A 'Value' of a number of coins issued in the STO
coins :: STOData -> Integer -> Value
coins d@STOData{stoTokenName} n =
    let sym = Value.mpsSymbol (mintingPolicyHash $ policy d)
    in Value.singleton sym stoTokenName n

PlutusTx.makeLift ''STOData
PlutusTx.unstableMakeIsData ''STOData
