{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
{-| Example trace for the uniswap contract
-}
module Plutus.Contracts.Uniswap.Trace(
    uniswapTrace
    --
    , setupTokens
    , tokenNames
    , wallets
    ) where

import Control.Monad (forM_, when)
import Control.Monad.Freer.Error (throwError)
import Data.Map qualified as Map
import Data.Monoid qualified as Monoid
import Data.Semigroup qualified as Semigroup
import Ledger
import Ledger.Ada (adaSymbol, adaToken)
import Ledger.Constraints
import Ledger.Value as Value
import Plutus.Contract as Contract hiding (throwError)
import Plutus.Contracts.Currency qualified as Currency
import Plutus.Contracts.Uniswap.OffChain as OffChain
import Plutus.Contracts.Uniswap.Types as Types
import Plutus.Trace.Emulator (EmulatorRuntimeError (GenericError), EmulatorTrace)
import Plutus.Trace.Emulator qualified as Emulator
import Wallet.Emulator (Wallet (..), knownWallet, knownWallets, walletPubKeyHash)

-- | Set up a liquidity pool and call the "add" endpoint
uniswapTrace :: EmulatorTrace ()
uniswapTrace = do
    cidInit <- Emulator.activateContract (knownWallet 1) setupTokens "init"
    _ <- Emulator.waitNSlots 5
    cs <- Emulator.observableState cidInit >>= \case
                Just (Semigroup.Last cur) -> pure (Currency.currencySymbol cur)
                _                         -> throwError $ GenericError "failed to create currency"
    let coins = Map.fromList [(tn, Types.mkCoin cs tn) | tn <- tokenNames]
        ada   = Types.mkCoin adaSymbol adaToken

    cidStart <- Emulator.activateContract (knownWallet 1) ownerEndpoint "start"
    _ <- Emulator.waitNSlots 5
    us <- Emulator.observableState cidStart >>= \case
                Monoid.Last (Just (Right v)) -> pure v
                _                            -> throwError $ GenericError "initialisation failed"
    cid1 <- Emulator.activateContractWallet (knownWallet 2) (awaitPromise $ userEndpoints us)
    cid2 <- Emulator.activateContractWallet (knownWallet 3) (awaitPromise $ userEndpoints us)
    _ <- Emulator.waitNSlots 5

    let cp = OffChain.CreateParams ada (coins Map.! "A") 100000 500000

    Emulator.callEndpoint @"create" cid1 cp
    _ <- Emulator.waitNSlots 5

    let ap = AddParams{apCoinA = ada, apCoinB = coins Map.! "A", apAmountA = 1000, apAmountB = 5000}
    Emulator.callEndpoint @"add" cid2 ap
    _ <- Emulator.waitNSlots 5
    pure ()

-- | Create some sample tokens and distribute them to
--   the emulated wallets
setupTokens :: Contract (Maybe (Semigroup.Last Currency.OneShotCurrency)) Currency.CurrencySchema Currency.CurrencyError ()
setupTokens = do
    ownPK <- Contract.ownPubKeyHash
    cur   <- Currency.mintContract ownPK [(tn, fromIntegral (length wallets) * amount) | tn <- tokenNames]
    let cs = Currency.currencySymbol cur
        v  = mconcat [Value.singleton cs tn amount | tn <- tokenNames]

    forM_ wallets $ \w -> do
        let pkh = walletPubKeyHash w
        when (pkh /= ownPK) $ do
            tx <- submitTx $ mustPayToPubKey pkh v
            awaitTxConfirmed $ getCardanoTxId tx

    tell $ Just $ Semigroup.Last cur

  where
    amount = 1000000

wallets :: [Wallet]
wallets = take 4 knownWallets

tokenNames :: [TokenName]
tokenNames = ["A", "B", "C", "D"]
