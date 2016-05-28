{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators   #-}

module Main where

import           Control.Concurrent                  (threadDelay)
import           Control.Concurrent.Async            (forConcurrently)
import           Data.Int                            (Int64)
import           Data.Maybe                          (fromMaybe)
import           Data.Time.Units                     (toMicroseconds)
import           Formatting                          (build, sformat, shown,
                                                      (%))
import           System.Clock                        (Clock (..), TimeSpec,
                                                      diffTimeSpec, getTime)

-- workaround to make stylish-haskell work :(
import           Options.Generic

import           System.IO.Temp                      (withSystemTempDirectory)

import           RSCoin.Core                         (PublicKey, SecretKey,
                                                      Severity (..),
                                                      initLogging, periodDelta)
import           RSCoin.User.Wallet                  (UserAddress)

import           BenchOnlyUsers.RSCoin.FilePathUtils (tempBenchDirectory)
import           BenchOnlyUsers.RSCoin.Logging       (initBenchLogger, logInfo)
import           BenchOnlyUsers.RSCoin.UserLogic     (benchUserTransactions,
                                                      initializeBank,
                                                      initializeUser,
                                                      userThread)

data BenchOptions = BenchOptions
    { users         :: Int            <?> "number of users"
    , severity      :: Maybe Severity <?> "severity for global logger"
    , benchSeverity :: Maybe Severity <?> "severity for bench logger"
    } deriving (Generic, Show)

instance ParseField  Severity
instance ParseFields Severity
instance ParseRecord Severity
instance ParseRecord BenchOptions

type KeyPairList = [(SecretKey, PublicKey)]

initializeUsers :: FilePath -> [Int64] -> IO [UserAddress]
initializeUsers benchDir userIds = do
    let initUserAction = userThread benchDir initializeUser
    logInfo $ sformat ("Initializing " % build % " users…") $ length userIds
    mapM initUserAction userIds

initializeSuperUser :: FilePath -> [UserAddress] -> IO ()
initializeSuperUser benchDir userAddresses = do
    -- give money to all users
    let bankId = 0
    logInfo "Initializaing user in bankMode…"
    userThread benchDir (const $ initializeBank userAddresses) bankId
    logInfo "Initialized user in bankMode, now waiting for the end of the period…"
    threadDelay $ fromInteger $ toMicroseconds (periodDelta + 1)

runTransactions :: FilePath -> [UserAddress] -> [Int64] -> IO (TimeSpec, TimeSpec)
runTransactions benchDir userAddresses userIds = do
    let benchUserAction =
            userThread benchDir $ benchUserTransactions userAddresses
    logInfo "Running transactions…"
    cpuTimeBefore <- getTime ProcessCPUTime
    wallTimeBefore <- getTime Realtime
    _ <- forConcurrently userIds benchUserAction
    wallTimeAfter <- getTime Realtime
    cpuTimeAfter <- getTime ProcessCPUTime
    return
        ( cpuTimeAfter `diffTimeSpec` cpuTimeBefore
        , wallTimeAfter `diffTimeSpec` wallTimeBefore)

main :: IO ()
main = do
    BenchOptions{..} <- getRecord "rscoin-bench-only-users"
    let userNumber      = unHelpful users
        globalSeverity  = fromMaybe Error $ unHelpful severity
        bSeverity       = fromMaybe Info   $ unHelpful benchSeverity
    withSystemTempDirectory tempBenchDirectory $ \benchDir -> do
        initLogging globalSeverity
        initBenchLogger bSeverity

        let userIds    = [1 .. fromIntegral userNumber]
        userAddresses <- initializeUsers benchDir userIds
        initializeSuperUser benchDir userAddresses

        (cpuTime, wallTime) <- runTransactions benchDir userAddresses userIds
        logInfo $ sformat ("Elapsed CPU time: " % shown) cpuTime
        logInfo $ sformat ("Elapsed wall-clock time: " % shown) wallTime