{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleContexts #-}


-- | All types.


module Types
    ( Config(..)
    , NodeComment(..)
    , NodeInfo(..)
    , PrintState(..)
    , Printer(..)
    , SomeComment(..)
    , defaultConfig
    , readExtension
    ) where


import Control.Applicative
import Control.Monad
import Control.Monad.State.Strict (MonadState(..), StateT)
import Control.Monad.Trans.Maybe
import Data.ByteString.Builder
import Data.Functor.Identity
import Data.Int (Int64)
import Data.Maybe
import Data.Yaml (FromJSON(..))
import qualified Data.Yaml as Y
import Language.Haskell.Exts hiding (Pretty, Style, parse, prettyPrint, style)


-- | A pretty printing monad.


newtype Printer a =
    Printer
        { runPrinter :: StateT PrintState (MaybeT Identity) a
        }
    deriving
        ( Applicative
        , Monad
        , Functor
        , MonadState PrintState
        , MonadPlus
        , Alternative
        )


-- | The state of the pretty printer.


data PrintState
    = PrintState
        { psIndentLevel :: !Int64
        , psColumnStart :: !Int64
        -- ^ Current indentation level, i.e. every time there's a
        -- new-line, output this many spaces.
        , psOutput :: !Builder
        -- ^ The current output bytestring builder.
        , psNewline :: !Bool
        -- ^ Just outputted a newline?
        , psColumn :: !Int64
        -- ^ Current column.
        , psLine :: !Int64
        -- ^ Current line number.
        , psConfig :: !Config
        -- ^ Configuration of max colums and indentation style.
        , psInsideCase :: !Bool
        , psInsideLetStatement :: !Bool
        -- ^ Whether we're in a case statement, used for Rhs printing.
        , psFitOnOneLine :: !Bool
        -- ^ Bail out if we need to print beyond the current line or
        -- the maximum column.
        , psEolComment :: !Bool
        }


-- | Configurations shared among the different styles. Styles may pay
-- attention to or completely disregard this configuration.


data Config
    = Config
        { configMaxColumns :: !Int64 -- ^ Maximum columns to fit code into ideally.
        , configMaxCodeColumns :: !Int64
        , configIndentSpaces :: !Int64 -- ^ How many spaces to indent?
        , configLineBreaksBefore :: [String] -- ^ Break line when meets these operators.
        , configLineBreaksAfter :: [String] -- ^ Break line when meets these operators.
        , configExtensions :: [Extension]
        }


-- | Parse an extension.
-- ^ Extra language extensions enabled by default.


readExtension :: (Monad m, MonadFail m) => String -> m Extension
readExtension x =
    case
        classifyExtension x -- Foo
    of
        UnknownExtension _ ->
            fail ("Unknown extension: " ++ x)

        x' ->
            return x'


instance FromJSON Config where
    parseJSON (Y.Object v) =
        Config
            <$> fmap
                (fromMaybe (configMaxColumns defaultConfig))
                (v Y..:? "line-length")
            <*> fmap
                (fromMaybe (configMaxCodeColumns defaultConfig))
                (v Y..:? "code-length")
            <*> fmap
                (fromMaybe (configIndentSpaces defaultConfig))
                (v Y..:? "indent-size" <|> v Y..:? "tab-size")
            <*> fmap
                (fromMaybe (configLineBreaksBefore defaultConfig))
                (v Y..:? "line-breaks-before")
            <*> fmap
                (fromMaybe (configLineBreaksAfter defaultConfig))
                (v Y..:? "line-breaks-after")
            <*>
                ( traverse readExtension
                    =<< fmap (fromMaybe []) (v Y..:? "extensions")
                )

    parseJSON _ =
        fail "Expected Object for Config value"


-- | Default style configuration.


defaultConfig :: Config
defaultConfig =
    Config
        { configMaxColumns = 80
        , configMaxCodeColumns = 80
        , configIndentSpaces = 4
        , configLineBreaksBefore = [ "|>" ]
        , configLineBreaksAfter = [ "<|" ]
        , configExtensions = []
        }


-- | Some comment to print.


data SomeComment
    = EndOfLine String
    | MultiLine String
    deriving (Show, Ord, Eq)


-- | Comment associated with a node.
-- 'SrcSpan' is the original source span of the comment.


data NodeComment
    = CommentSameLine SrcSpan SomeComment
    | CommentBeforeLine SrcSpan SomeComment
    | TopLevelCommentBeforeLine SrcSpan SomeComment
    | TopLevelCommentAfterLine SrcSpan SomeComment
    deriving (Show, Ord, Eq)


-- | Information for each node in the AST.


data NodeInfo
    = NodeInfo
        { nodeInfoSpan :: !SrcSpanInfo -- ^ Location info from the parser.
        , nodeInfoComments :: ![NodeComment] -- ^ Comments attached to this node.
        , linePrefix :: !String
        }


instance Show NodeInfo where
    show (NodeInfo _ [] _) =
        ""

    show (NodeInfo _ s _) =
        "{- " ++ show s ++ " -}"
