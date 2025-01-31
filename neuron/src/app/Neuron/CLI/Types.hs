{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.CLI.Types
  ( -- * CLI
    AppConfig (..),
    Env (..),

    -- * App monad
    App,
    getAppEnv,
    runApp,
    MonadApp (..),

    -- * CLI commands
    Command (..),
    NewCommand (..),
    SearchBy (..),
    SearchCommand (..),
    OpenCommand (..),
    QueryCommand (..),
    GenCommand (..),
  )
where

import Colog
  ( HasLog (getLogAction, setLogAction),
    LogAction,
    log,
  )
import Data.Some (Some (..))
import Data.Time.DateMayTime
  ( DateMayTime,
  )
import Neuron.CLI.Logging
import qualified Neuron.Frontend.Route as R
import Neuron.Zettelkasten.ID.Scheme (IDScheme (..))
import Neuron.Zettelkasten.Query.Graph as Q (GraphQuery (..))
import Neuron.Zettelkasten.Zettel as Q
  ( ZettelQuery (..),
  )
import Relude
import System.FilePath ((</>))

data AppConfig = AppConfig
  { notesDir :: FilePath,
    outputDir :: Maybe FilePath,
    cmd :: Command
  }
  deriving (Show)

data Env m = Env
  { envAppConfig :: AppConfig,
    envLogAction :: LogAction m Message
  }

instance HasLog (Env m) Message m where
  getLogAction :: Env m -> LogAction m Message
  getLogAction = envLogAction
  {-# INLINE getLogAction #-}

  setLogAction :: LogAction m Message -> Env m -> Env m
  setLogAction newLogAction env = env {envLogAction = newLogAction}
  {-# INLINE setLogAction #-}

newtype App a = App (ReaderT (Env App) IO a)
  deriving newtype (Functor, Applicative, Monad, MonadIO)
  deriving newtype (MonadReader (Env App))

instance MonadFail App where
  fail s = do
    log EE $ indentAllButFirstLine 4 $ toText s
    exitFailure

getAppEnv :: App (Env App)
getAppEnv = App ask

runApp :: Env App -> App a -> IO a
runApp appEnv (App m) = do
  runReaderT m appEnv

class MonadApp m where
  getNotesDir :: m FilePath
  getOutputDir :: m FilePath
  getCommand :: m Command

instance MonadApp App where
  getNotesDir =
    App $ reader $ notesDir . envAppConfig
  getOutputDir = do
    mOut <- App $ reader $ outputDir . envAppConfig
    case mOut of
      Nothing ->
        getNotesDir <&> (</> ".neuron" </> "output")
      Just fp ->
        pure fp
  getCommand =
    App $ reader $ cmd . envAppConfig

data NewCommand = NewCommand
  { date :: DateMayTime,
    idScheme :: Some IDScheme,
    edit :: Bool
  }
  deriving (Eq, Show)

data SearchCommand = SearchCommand
  { searchBy :: SearchBy,
    searchEdit :: Bool
  }
  deriving (Eq, Show)

data SearchBy
  = SearchByTitle
  | SearchByContent
  deriving (Eq, Show)

newtype OpenCommand = OpenCommand
  { unOpenCommand :: Some R.Route
  }
  deriving (Eq, Show)

data QueryCommand = QueryCommand
  { -- Use cache instead of building the zettelkasten from scratch
    cached :: Bool,
    query :: Either (Some Q.ZettelQuery) (Some Q.GraphQuery)
  }
  deriving (Eq, Show)

data GenCommand = GenCommand
  { -- | Whether to run a HTTP server on `outputDir`
    serve :: Maybe (Text, Int),
    watch :: Bool
  }
  deriving (Eq, Show)

data Command
  = -- | Create a new zettel file
    New NewCommand
  | -- | Open the locally generated Zettelkasten
    Open OpenCommand
  | -- | Search a zettel by title
    Search SearchCommand
  | -- | Run a query against the Zettelkasten
    Query QueryCommand
  | -- | Run site generation
    Gen GenCommand
  deriving (Eq, Show)
