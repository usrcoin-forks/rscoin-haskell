-- | Re-export functionality from RSCoin.User.* modules

module RSCoin.User
       (
         module Exports
       , getAllAddresses
       ) where

import           Control.Lens           ((^.))
import           Control.Monad.Trans    (MonadIO)

import           RSCoin.User.AcidState  as Exports
import           RSCoin.User.Cache      as Exports
import           RSCoin.User.Error      as Exports
import           RSCoin.User.Logic      as Exports
import           RSCoin.User.Operations as Exports
import           RSCoin.User.Wallet     as Exports hiding (addAddress,
                                                    getLastBlockId,
                                                    isInitialized)

import qualified RSCoin.Core            as C

getAllAddresses :: MonadIO m => UserState -> C.NodeContext -> m [C.Address]
getAllAddresses s nodeCtx =
    query s $ GetOwnedDefaultAddresses (nodeCtx ^. C.genesisAddress)
