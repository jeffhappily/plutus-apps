{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE DerivingStrategies   #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Plutus.Trace.Emulator.Types(
    EmulatorMessage(..)
    , EmulatorThreads(..)
    , instanceIdThreads
    , EmulatorAgentThreadEffs
    , EmulatedWalletEffects
    , EmulatedWalletEffects'
    , ContractInstanceTag(..)
    , walletInstanceTag
    , ContractHandle(..)
    , Emulator
    , ContractConstraints
    -- * Instance state
    , ContractInstanceState(..)
    , ContractInstanceStateInternal(..)
    , emptyInstanceState
    , addEventInstanceState
    , toInstanceState
    -- * Logging
    , ContractInstanceLog(..)
    , cilId
    , cilMessage
    , cilTag
    , EmulatorRuntimeError(..)
    , ContractInstanceMsg(..)
    , _Started
    , _StoppedNoError
    , _StoppedWithError
    , _ReceiveEndpointCall
    , _NoRequestsHandled
    , _HandledRequest
    , _CurrentRequests
    , _InstErr
    , _ContractLog
    , UserThreadMsg(..)
    ) where

import Control.Lens
import Control.Monad.Freer.Coroutine
import Control.Monad.Freer.Error
import Control.Monad.Freer.Extras.Log (LogMessage, LogMsg, LogObserve)
import Control.Monad.Freer.Reader (Reader)
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as JSON
import Data.Map (Map)
import Data.Row (Row)
import Data.Row.Internal qualified as V
import Data.Sequence (Seq)
import Data.String (IsString (..))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Ledger.Blockchain (Block)
import Ledger.Slot (Slot (..))
import Plutus.ChainIndex (ChainIndexQueryEffect)
import Plutus.Contract (Contract (..), WalletAPIError)
import Plutus.Contract.Effects (PABReq, PABResp)
import Plutus.Contract.Resumable (Request (..), Requests (..), Response (..))
import Plutus.Contract.Resumable qualified as State
import Plutus.Contract.Schema (Input, Output)
import Plutus.Contract.Types (ResumableResult (..), SuspendedContract (..))
import Plutus.Contract.Types qualified as Contract.Types
import Plutus.Trace.Scheduler (AgentSystemCall, ThreadId)
import Prettyprinter (Pretty (..), braces, colon, fillSep, hang, parens, squotes, viaShow, vsep, (<+>))
import Wallet.API qualified as WAPI
import Wallet.Effects (NodeClientEffect, WalletEffect)
import Wallet.Emulator.LogMessages (RequestHandlerLogMsg, TxBalanceMsg)
import Wallet.Emulator.Wallet (Wallet (..))
import Wallet.Types (ContractInstanceId, EndpointDescription, Notification (..), NotificationError)

type ContractConstraints s =
    ( V.Forall (Output s) V.Unconstrained1
    , V.Forall (Input s) V.Unconstrained1
    , V.AllUniqueLabels (Input s)
    , V.AllUniqueLabels (Output s)
    , V.Forall (Input s) JSON.FromJSON
    , V.Forall (Input s) JSON.ToJSON
    , V.Forall (Output s) JSON.FromJSON
    , V.Forall (Output s) JSON.ToJSON
    )

-- | Messages sent to, and received by, threads in the emulator.
data EmulatorMessage =
    NewSlot [Block] Slot -- ^ A new slot has begun and some blocks were added.
    | EndpointCall ThreadId EndpointDescription JSON.Value -- ^ Call to an endpoint
    | Freeze -- ^ Tell the contract instance to freeze itself (see note [Freeze and Thaw])
    | ContractInstanceStateRequest ThreadId -- ^ Request for the current state of a contract instance
    | ContractInstanceStateResponse JSON.Value -- ^ Response to a contract instance state request
    deriving stock (Eq, Show)

-- | A map of contract instance ID to thread ID
newtype EmulatorThreads =
    EmulatorThreads
        { _instanceIdThreads :: Map ContractInstanceId ThreadId
        } deriving newtype (Semigroup, Monoid)

makeLenses ''EmulatorThreads

-- | Effects that are used to handle requests by contract instances.
--   In the emulator these effects are handled by 'Wallet.Emulator.MultiAgent'.
--   In the PAB they are handled by the actual wallet/node/chain index,
--   mediated by the PAB runtime.
type EmulatedWalletEffects' effs =
        WalletEffect
        ': Error WAPI.WalletAPIError
        ': NodeClientEffect
        ': ChainIndexQueryEffect
        ': LogObserve (LogMessage T.Text)
        ': LogMsg RequestHandlerLogMsg
        ': LogMsg TxBalanceMsg
        ': LogMsg T.Text
        ': effs

type EmulatedWalletEffects = EmulatedWalletEffects' '[]

-- | Effects available to emulator agent threads. Includes emulated wallet
--   effects and effects related to threading / waiting for messages.
type EmulatorAgentThreadEffs effs =
    LogMsg ContractInstanceLog

    ': EmulatedWalletEffects' (
        Yield (AgentSystemCall EmulatorMessage) (Maybe EmulatorMessage)
        ': Reader ThreadId
        ': effs
        )

data Emulator

-- | A reference to a running contract in the emulator.
data ContractHandle w s e =
    ContractHandle
        { chContract    :: Contract w s e ()
        , chInstanceId  :: ContractInstanceId
        , chInstanceTag :: ContractInstanceTag
        }

data EmulatorRuntimeError =
    ThreadIdNotFound ContractInstanceId
    | InstanceIdNotFound Wallet
    | EmulatorJSONDecodingError String JSON.Value
    | GenericError String
    | EmulatedWalletError WalletAPIError
    | AssertionError String
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty EmulatorRuntimeError where
    pretty = \case
        ThreadIdNotFound i            -> "Thread ID not found:" <+> pretty i
        InstanceIdNotFound w          -> "Instance ID not found:" <+> pretty w
        EmulatorJSONDecodingError e v -> "Emulator JSON decoding error:" <+> pretty e <+> parens (viaShow v)
        AssertionError n              -> "Assertion failed: " <+> (squotes $ pretty n)
        GenericError e                -> pretty e
        EmulatedWalletError e         -> pretty e

-- | A user-defined tag for a contract instance. Used to find the instance's
--   log messages in the emulator log.
newtype ContractInstanceTag = ContractInstanceTag { unContractInstanceTag :: Text }
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
    deriving newtype (IsString, Pretty, Semigroup, Monoid)

-- | The 'ContractInstanceTag' for the contract instance of a wallet. See note
--   [Wallet contract instances]
walletInstanceTag :: Wallet -> ContractInstanceTag
walletInstanceTag (Wallet i) = fromString $ "Contract instance for wallet " <> show i

-- | Log message produced by the user (main) thread
data UserThreadMsg =
    UserThreadErr EmulatorRuntimeError
    | UserLog String
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty UserThreadMsg where
    pretty = \case
        UserLog str     -> pretty str
        UserThreadErr e -> "Error:" <+> pretty e

-- | Log messages produced by contract instances
data ContractInstanceMsg =
    Started
    | StoppedNoError
    | StoppedWithError String
    | ReceiveEndpointCall EndpointDescription JSON.Value
    | ReceiveEndpointCallSuccess
    | ReceiveEndpointCallFailure NotificationError
    | NoRequestsHandled
    | HandledRequest (Response JSON.Value)
    | CurrentRequests [Request JSON.Value]
    | InstErr EmulatorRuntimeError
    | ContractLog JSON.Value
    | SendingNotification Notification
    | NotificationSuccess Notification
    | NotificationFailure NotificationError
    | SendingContractState ThreadId
    | Freezing
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty ContractInstanceMsg where
    pretty = \case
        Started -> "Contract instance started"
        StoppedNoError -> "Contract instance stopped (no errors)"
        StoppedWithError e -> "Contract instance stopped with error:" <+> pretty e
        ReceiveEndpointCall d v -> "Receive endpoint call on" <+> squotes (pretty d) <+> "for" <+> viaShow v
        ReceiveEndpointCallSuccess -> "Endpoint call succeeded"
        ReceiveEndpointCallFailure f -> "Endpoint call failed:" <+> pretty f
        NoRequestsHandled -> "No requests handled"
        HandledRequest rsp -> "Handled request:" <+> pretty (take 50 . show . JSON.encode <$> rsp)
        CurrentRequests lst -> "Current requests" <+> parens (pretty (length lst)) <> colon <+> fillSep (pretty . fmap (take 50 . show . JSON.encode) <$> lst)
        InstErr e -> "Error:" <+> pretty e
        ContractLog v -> "Contract log:" <+> viaShow v
        SendingNotification Notification{notificationContractID,notificationContractEndpoint} ->
            "Sending notification" <+> pretty notificationContractEndpoint <+> "to" <+> pretty notificationContractID
        NotificationSuccess Notification{notificationContractID,notificationContractEndpoint} ->
            "Notification" <+> pretty notificationContractEndpoint <+> "of" <+> pretty notificationContractID <+> "succeeded"
        NotificationFailure e ->
            "Notification failed:" <+> viaShow e
        Freezing -> "Freezing contract instance"
        SendingContractState t -> "Sending contract state to" <+> pretty t

data ContractInstanceLog =
    ContractInstanceLog
        { _cilMessage :: ContractInstanceMsg
        , _cilId      :: ContractInstanceId
        , _cilTag     :: ContractInstanceTag
        }
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty ContractInstanceLog where
    pretty ContractInstanceLog{_cilMessage, _cilId, _cilTag} =
        hang 2 $ vsep [pretty _cilId <+> braces (pretty _cilTag) <> colon, pretty _cilMessage]

-- | State of the contract instance, internal to the contract instance thread.
--   It contains both the serialisable state of the contract instance and the
--   non-serialisable continuations in 'SuspendedContract'.
data ContractInstanceStateInternal w (s :: Row *) e a =
    ContractInstanceStateInternal
        { cisiSuspState       :: SuspendedContract w e PABResp PABReq a
        , cisiEvents          :: Seq (Response PABResp)
        , cisiHandlersHistory :: Seq [State.Request PABReq]
        }

-- | Extract the serialisable 'ContractInstanceState' from the
--   'ContractInstanceStateInternal'. We need to do this when
--   we want to send the instance state to another thread.
toInstanceState :: ContractInstanceStateInternal w (s :: Row *) e a -> ContractInstanceState w s e a
toInstanceState ContractInstanceStateInternal{cisiSuspState=SuspendedContract{_resumableResult}, cisiEvents, cisiHandlersHistory} =
    ContractInstanceState
        { instContractState = _resumableResult
        , instEvents = cisiEvents
        , instHandlersHistory = cisiHandlersHistory
        }

-- | The state of a running contract instance with schema @s@ and error type @e@
--   Serialisable to JSON.
data ContractInstanceState w (s :: Row *) e a =
    ContractInstanceState
        { instContractState   :: ResumableResult w e PABResp PABReq a
        , instEvents          :: Seq (Response PABResp) -- ^ Events received by the contract instance. (Used for debugging purposes)
        , instHandlersHistory :: Seq [State.Request PABReq] -- ^ Requests issued by the contract instance (Used for debugging purposes)
        }
        deriving stock Generic

deriving anyclass instance  (JSON.ToJSON e, JSON.ToJSON a, JSON.ToJSON w) => JSON.ToJSON (ContractInstanceState w s e a)
deriving anyclass instance  (JSON.FromJSON e, JSON.FromJSON a, JSON.FromJSON w) => JSON.FromJSON (ContractInstanceState w s e a)

emptyInstanceState ::
    forall w (s :: Row *) e a.
    Monoid w
    => Contract w s e a
    -> ContractInstanceStateInternal w s e a
emptyInstanceState (Contract c) =
    ContractInstanceStateInternal
        { cisiSuspState = Contract.Types.suspend mempty c
        , cisiEvents = mempty
        , cisiHandlersHistory = mempty
        }

addEventInstanceState :: forall w s e a.
    Monoid w
    => Response PABResp
    -> ContractInstanceStateInternal w s e a
    -> Maybe (ContractInstanceStateInternal w s e a)
addEventInstanceState event ContractInstanceStateInternal{cisiSuspState, cisiEvents, cisiHandlersHistory} =
    case Contract.Types.runStep cisiSuspState event of
        Nothing -> Nothing
        Just newState ->
            let SuspendedContract{_resumableResult=ResumableResult{_requests=Requests rq}} = cisiSuspState in
            Just ContractInstanceStateInternal
                { cisiSuspState = newState
                , cisiEvents = cisiEvents |> event
                , cisiHandlersHistory = cisiHandlersHistory |> rq
                }

makeLenses ''ContractInstanceLog
makePrisms ''ContractInstanceMsg


-- | What to do when the initial thread finishes.
data OnInitialThreadStopped =
    KeepGoing -- ^ Keep going until all threads have finished.
    | Stop -- ^ Stop right away.
    deriving stock (Eq, Ord, Show)
