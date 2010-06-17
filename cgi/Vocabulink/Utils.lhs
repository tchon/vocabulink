% Copyright 2008, 2009, 2010 Chris Forno

% This file is part of Vocabulink.

% Vocabulink is free software: you can redistribute it and/or modify it under
% the terms of the GNU Affero General Public License as published by the Free
% Software Foundation, either version 3 of the License, or (at your option) any
% later version.

% Vocabulink is distributed in the hope that it will be useful, but WITHOUT ANY
% WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
% A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
% details.

% You should have received a copy of the GNU Affero General Public License
% along with Vocabulink. If not, see <http://www.gnu.org/licenses/>.

\section{Utility Functions}

Here are some functions that aren't specific to Vocabulink, but that don't
exist in any libraries I know of. We also use this module to export some
oft-used functions for other modules.

> module Vocabulink.Utils (         if', (?), safeHead, currentDay, currentYear,
>                                   formatSimpleTime, basename, translate, (<$$>),
>                                   sendMail, every2nd, every3rd, splitLines,
>                                   convertLineEndings, logError,
>  {- Codec.Binary.UTF8.String -}   encodeString, decodeString,
>  {- Control.Applicative -}        pure, (<$>), (<*>),
>  {- Control.Applicative.Error -}  Failing(..), maybeRead,
>  {- Control.Arrow -}              first, second,
>  {- Control.Exception -}          SomeException,
>  {- Control.Monad -}              liftM,
>  {- Control.Monad.Trans -}        liftIO, MonadIO,
>  {- Data.Char -}                  toLower,
>  {- Data.Either.Utils -}          forceEither,
>  {- Data.List -}                  intercalate, partition,
>  {- Data.Maybe -}                 maybe, fromMaybe, fromJust, isJust, isNothing,
>                                   mapMaybe, catMaybes,
>  {- Data.Time.Calendar -}         Day,
>  {- Data.Time.Clock -}            UTCTime, getCurrentTime, diffUTCTime,
>  {- Data.Time.Format -}           formatTime,
>  {- Data.Time.LocalTime -}        ZonedTime,
>  {- System.FilePath -}            (</>), (<.>), takeExtension,
>                                   replaceExtension, takeBaseName, takeFileName,
>  {- System.Locale -}              defaultTimeLocale, rfc822DateFormat,
>  {- System.Posix.Files -}         getFileStatus, modificationTime,
>  {- System.Posix.Types -}         EpochTime) where

> import Codec.Binary.UTF8.String (encodeString, decodeString)

Applicative was first introduced to Vocabulink for working with Formlets.
However, it seems to be a style that the Haskell community is using more and
more.

> import Control.Applicative (pure, (<$>), (<*>))
> import Control.Applicative.Error (Failing(..), maybeRead)

> import Control.Arrow (first, second)

> import Control.Exception (SomeException)

We make particularly extensive use of |liftM| and the Maybe monad.

> import Control.Monad (liftM)
> import Control.Monad.Trans (liftIO, MonadIO)
> import Data.Char (toLower)
> import Data.Either.Utils (forceEither) -- MissingH
> import Data.List (intercalate, partition)
> import Data.List.Utils (join) -- MissingH
> import Data.Maybe (fromMaybe, fromJust, isJust, isNothing, mapMaybe, catMaybes)

Time is notoriously difficult to deal with in Haskell. It gets especially
tricky when working with the database and libraries that expect different
formats.

> import Data.Time.Calendar (Day, toGregorian)
> import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
> import Data.Time.Format (formatTime)
> import Data.Time.LocalTime (  getCurrentTimeZone, utcToLocalTime,
>                               LocalTime(..), ZonedTime)
> import System.Cmd (system)
> import System.Exit (ExitCode(..))
> import System.FilePath (  (</>), (<.>), takeExtension, replaceExtension,
>                           takeBaseName, takeFileName )
> import System.IO (hPutStrLn, stderr)
> import System.IO.Error (try)
> import System.Locale (defaultTimeLocale, rfc822DateFormat)
> import System.Posix.Files (getFileStatus, modificationTime)
> import System.Posix.Types (EpochTime)

It's often useful to have the compactness of the traditional tertiary operator
rather than an if then else. The |(?)| operator can be used like:

\begin{quote}|Bool ? trueExpression $ falseExpression|\end{quote}

I think I originally saw this defined on the Haskell wiki.

> infixl 1 ?
> (?)  :: Bool -> a -> a -> a
> (?)  = if'

> if' :: Bool -> a -> a -> a
> if' True   x  _  = x
> if' False  _  y  = y

\subsection{Time}

Return the current day. I'm not sure that this is useful on its own.

> currentDay :: IO Day
> currentDay = do
>   now  <- getCurrentTime
>   tz   <- getCurrentTimeZone
>   let (LocalTime day _) = utcToLocalTime tz now
>   return day

Return the current year as a 4-digit number.

> currentYear :: IO Integer
> currentYear = do
>   day <- currentDay
>   let (year, _, _) = toGregorian day
>   return year

Displaying a time is a common enough task.

> formatSimpleTime :: UTCTime -> String
> formatSimpleTime = formatTime defaultTimeLocale "%a %b %d, %Y %R"

For files we receive via HTTP, we can't make assumptions about the path
separator.

> basename :: FilePath -> FilePath
> basename = reverse . takeWhile (`notElem` "/\\") . reverse

This is like the Unix tr utility. It takes a list of search/replacements and
then performs them on the list.

> translate :: (Eq a) => [(a, a)] -> [a] -> [a]
> translate sr = map (\s -> fromMaybe s $ lookup s sr)

Often it's handy to be able to lift an operation into 2 monads with little
verbosity. Parsec may have claimed this operator name before me, but |<$$>|
just makes too much sense as 2 |<$>|s.

> (<$$>) :: (Monad m1, Monad m) => (a -> r) -> m (m1 a) -> m (m1 r)
> (<$$>) = liftM . liftM

Sending mail is pretty easy. We just deliver it to a local MTA. Even if we have
no MTA running locally, there are sendmail emulators that will handle the SMTP
forwarding for us so that we don't have to deal with SMTP here.

> sendMail :: String -> String -> String -> IO (Maybe ())
> sendMail to subject body = do
>   let body' = unlines [  "To: <" ++ to ++ ">",
>                          "Subject: " ++ subject,
>                          "",
>                          body ]
>   res <- try $ system
>            (  "export MAILUSER=vocabulink; \
>               \export MAILHOST=vocabulink.com; \
>               \export MAILNAME=Vocabulink; \
>               \echo -e \""   ++ body'  ++ "\" | \
>               \sendmail \""  ++ to     ++ "\"" )
>   case res of
>     Right ExitSuccess  -> return $ Just ()
>     _                  -> return Nothing

\subsection{Lists}

In case we want don't want our program to crash when taking the head of the
empty list, we need to provide a default:

> safeHead :: a -> [a] -> a
> safeHead d []     = d
> safeHead _ (x:_)  = x

If we want to layout items from left to right in HTML columns, we need to break
1 list down into smaller lists. |everyNth| is not a great name, but |cycleN| is
equally confusing. These use a neat |foldr| trick I found on the Haskell wiki.

every2nd [1,2,3] =>
3 ([],[]) => ([3],[])
2 ([3],[]) => ([2],[3])
1 ([2],[3]) => ([1,3],[2])

> every2nd :: [a] -> ([a], [a])
> every2nd = foldr (\a ~(x,y) -> (a:y,x)) ([],[])

every3rd [1,2,3,4,5] =>
5 ([],[],[]) => ([5],[],[])
4 ([5],[],[]) => ([4],[5],[])
3 ([4],[5],[]) => ([3],[4],[5])
2 ([3],[4],[5]) => ([2,5],[3],[4])
1 ([2,5],[3],[4]) => ([1,4],[2,5],[3])

> every3rd :: [a] -> ([a], [a], [a])
> every3rd = foldr (\a ~(x,y,z) -> (a:z,x,y)) ([],[],[])

We might get data from various sources that use different end-of-line
terminators. But we want to always work with just newlines.

We use |join| instead of |unlines| because |unlines| adds a trailing newline.

> convertLineEndings :: String -> String
> convertLineEndings = join "\n" . splitLines

This comes from Real World Haskell.

> splitLines :: String -> [String]
> splitLines []  = []
> splitLines cs  =
>   let (pre, suf) = break isLineTerminator cs in
>   pre : case suf of
>           ('\r':'\n':rest)  -> splitLines rest
>           ('\r':rest)       -> splitLines rest
>           ('\n':rest)       -> splitLines rest
>           _                 -> []

> isLineTerminator :: Char -> Bool
> isLineTerminator c = c == '\r' || c == '\n'

Log a message to standard error.

> logError :: String -> String -> IO ()
> logError typ msg = hPutStrLn stderr $ "[" ++ typ ++ "] " ++ msg