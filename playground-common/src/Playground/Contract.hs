-- | Re-export functions that are needed when creating a Contract for use in the playground
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE ExplicitNamespaces  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE MonoLocalBinds      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}

module Playground.Contract
    ( mkFunctions
    , mkFunction
    , endpointsToSchemas
    , ensureKnownCurrencies
    , mkSchemaDefinitions
    , mkKnownCurrencies
    , ToSchema
    , ToArgument
    , ToJSON
    , FromJSON
    , FunctionSchema
    , FormSchema
    , Generic
    , printSchemas
    , printJson
    , IO
    , Show
    , Wallet(..)
    , module Playground.Interpreter.Util
    , KnownCurrency(KnownCurrency)
    , ValidatorHash(ValidatorHash)
    , TokenName(TokenName)
    , NonEmpty((:|))
    , adaCurrency
    , endpoint
    , Contract
    , Endpoint
    , AsContractError
    , TraceError(..)
    , type (.\/)
    , interval
    , ownPubKeyHash
    , awaitSlot
    , modifiesUtxoSet
    , utxosAt
    , watchAddressUntilSlot
    , submitTx
    , Tx
    , TxOutRef(TxOutRef, txOutRefId)
    , Expression
    ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as JSON
import Data.ByteString.Lazy.Char8 qualified as LBC8
import Data.List.NonEmpty (NonEmpty ((:|)))
import GHC.Generics (Generic)
import Ledger.Constraints (modifiesUtxoSet)
import Ledger.Interval (interval)
import Ledger.Scripts (ValidatorHash (ValidatorHash))
import Ledger.Tx (Tx, TxOutRef (TxOutRef), txOutRefId)
import Ledger.Value (TokenName (TokenName))
import Playground.Interpreter.Util
import Playground.Schema (endpointsToSchemas)
import Playground.TH (ensureKnownCurrencies, mkFunction, mkFunctions, mkKnownCurrencies, mkSchemaDefinitions)
import Playground.Types (Expression, FunctionSchema, KnownCurrency (KnownCurrency), adaCurrency)
import Plutus.Contract (AsContractError, Contract, Endpoint, awaitSlot, endpoint, ownPubKeyHash, submitTx, type (.\/),
                        utxosAt, watchAddressUntilSlot)
import Plutus.Contract.Trace (TraceError (..))
import Schema (FormSchema, ToArgument, ToSchema)
import Wallet.Emulator.Types (Wallet (..))

printSchemas :: ([FunctionSchema FormSchema], [KnownCurrency]) -> IO ()
printSchemas (userSchemas, currencies) =
    LBC8.putStrLn . JSON.encode $ (allSchemas, currencies)
  where
    allSchemas = userSchemas <> builtinSchemas
    builtinSchemas = []

printJson :: ToJSON a => a -> IO ()
printJson = LBC8.putStrLn . JSON.encode
