% Copyright 2008, 2009 Chris Forno

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

\documentclass[oneside]{article}
%include polycode.fmt
\usepackage[T1]{fontenc}
\usepackage{ucs}
\usepackage[utf8]{inputenc}
\usepackage{hyperref}
\usepackage[pdftex]{graphicx}
\usepackage[x11names, rgb]{xcolor}
\usepackage{tikz}
\usetikzlibrary{decorations,arrows,shapes}
\usepackage[margin=1.4in]{geometry}

\hypersetup{colorlinks=true}

\title{Vocabulink}
\author{Chris Forno (jekor)}
\date{May 3rd, 2009}

\begin{document}
\maketitle

\section{Introduction}

This is Vocabulink, the FastCGI process that handles all web requests for\\*
\url{http://www.vocabulink.com/}.

Vocabulink is essentially a multi-user application that operates via the web.
It's structured like a standalone application inasmuch as it handles multiple
requests in a multi-threaded process. Yet, it operates as a CGI program. It's
designed with the assumption that it may be only 1 of many processes servicing
requests and that it doesn't have exclusive access to resources such as a
database.

The program is built with GHC 6.8.3 using options @-Wall -fglasgow-exts
-threaded@ and with @-package fastcgi@. I keep the build free from warnings at
all times (which sometimes leads to a few oddities in the source). It has been
tested on GNU/Linux.

\subsection{Copyright Notice}

Copyright 2008, 2009 Chris Forno

Vocabulink is free software: you can redistribute it and/or modify it under the
terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

Vocabulink is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Vocabulink. If not, see \url{http://www.gnu.org/licenses/}.

\subsection{Architecture}

Requests arrive via a webserver.\footnote{I'm currently using nginx on
www.vocabulink.com, but it should work with any server that supports FastCGI.}
They are passed to the vocabulink.fcgi process (this program) on TCP port 10033
of the local loopback interface.

Upon receiving a request (connection), we immediately fork a new thread. In
this thread, we establish a connection to a PostgreSQL server (for each
request). We then examine the thread for an authentication cookie. If it exists
and is valid, we consider the request to have originated from an authenticated
member. We pack both the database handle and the authenticated member
information into our ``App'' monad (\autoref{App}).

> module Main where

\section{Our Modules}

These are the Vocabulink modules we need from the toplevel. They are grouped
primarily based on division of labor. The exception is the App module. The App
module defines the App monad and must make use of both database and CGI
functions. In order to limit cyclical dependencies, it's broken out into a
separate module.

> import Vocabulink.App

Each of these modules will be described in its own section.

> import Vocabulink.Article
> import Vocabulink.DB
> import Vocabulink.CGI
> import Vocabulink.Comment
> import Vocabulink.Forum
> import Vocabulink.Html hiding (method, options)
> import Vocabulink.Link
> import Vocabulink.Member
> import Vocabulink.Review
> import Vocabulink.Utils

\section{Other Modules}

Vocabulink makes use of a half dozen or so Haskell libraries not included with
GHC. Even though we don't use them all in this module, I'll describe them here
so that they'll be more familiar as they're introduced.

\begin{description}

\item[Codec.Binary.UTF8.String] Vocabulink would be pretty useless without
being able to handle the writing systems of other languages. We only make use
of 2 functions provided by this library: |encodeString| and |decodeString|.
|decodeString| takes a UTF-8 string---either from the webserver or from the
database---and converts it into a Unicode string that can be used by Haskell
natively. We use |encodeString| to go in the other direction. Whenever we write
out a string to the database, the webserver, or a log file; it needs to be
encoded to UTF-8. This is something that the type system does not (yet) handle
for us, so we need to be careful to correctly encode and decode strings.

\item[Data.ConfigFile] We need to have some parameters configurable at runtime.
This allows us to do things differently in test and production environments. It
also allows us to publish the source to the program without exposing sensitive
information.

\item[Data.Digest.OpenSSL.HMAC] The nano-hmac library is used for generating
tokens for use in member authentication tokens.

\item[Database.HDBC] We make heavy use of PostgreSQL via HDBC, as Vocabulink is
a data-driven application. HDBC takes most of the work out of converting
between types when exchanging data with the database.

\item[Network.FastCGI] The FastCGI library provides a simple interface that's
mostly compatible with the Network.CGI library. I've modified the library
slightly so that it outputs using UTF-8 by default.\footnote{I haven't released
my changes to Network.FastCGI as I suspect there might be a better way to make
UTF-8 output more general (if it doesn't exist already). But I'd be happy to
share the changes if you're interested.}

\item[Network.Gravatar] The gravatar library is a simple and convenient way to
generate links to gravatar images. It was a bit of a pleasant surprise, and a
sign of Haskell's maturity, to find it.

\item[Network.Memcache] Interacting with memcached is very simple because it
uses a simple text protocol. However, a library already exists, so we take
advantage of it. As with Network.FastCGI, I slightly modified this one to use
UTF-8 output by default and to support the flush command.

\item[Network.URI] Various parts of the code may need to construct or
deconstruct URLs. Using this library should be safer than using various
string-mangling techniques throughout the code.

\item[Text.Formlets] Formlets are one of the unique advantages that we get from
working in a functional language. The Formlets library isn't perfect yet,
namely with the way field names are automatically generated, but it's useful
regardless.

\item[Text.JSON] We make use of the JSON encoding to sending data to web
browsers for AJAX-style interaction.

\item[Text.ParserCombinators.Parsec] We need to parse text from time to time.
The dispatcher, the member authentication routines, and the article publishing
system all make use of Parsec; and probably more will in the future.

\item[Text.Pandoc] Mnemonic stories and forum posts are handled by Pandoc using
the Markdown formatting syntax. The text is stored in Markdown syntax in the
database to avoid lossiness and is rendered by Pandoc upon retrieval. Note that
Pandoc is not responsible for formatting articles though (those are handled by
Muse Mode).

\end{description}

> import Control.Concurrent (forkIO)
> import Control.Monad (join)
> import Control.Monad.Error (runErrorT)
> import Data.ConfigFile (readfile, emptyCP, ConfigParser, CPError, options)
> import Data.List (find, intercalate, intersect)
> import Data.List.Split (splitOn)
> import Network.FastCGI (runFastCGIConcurrent')
> import Network.URI (URI(..), unEscapeString)

\section{Entry and Dispatch}

When the program starts, it immediately begin listening for connections.
|runFastCGIConcurrent'| spawns up to 2,048 threads. This matches the number
that nginx, running in front of vocabulink.cgi, is configured for.
|handleErrors'| and |runApp| will be explained later. They basically catch
unhandled database errors and pack information into the App monad.

Before forking, we read a configuration file. We pass this to runApp so that
all threads have access to global configuration information.

The first thing we do after forking is establish a database connection. The
database connection might be used immediately in order to log errors. It'll
eventually be passed to the App monad where it'll be packed into a reader
environment.

> main :: IO ()
> main = do  cp' <- getConfig
>            case cp' of
>              Left e    -> print e
>              Right cp  -> runFastCGIConcurrent' forkIO 2048 (do
>                c <- liftIO connect
>                handleErrors' c (runApp c cp handleRequest))

The path to the configuration file is the one bit of configuration that's the
same in all environments.

> configFile :: String
> configFile = "/etc/vocabulink.conf"

These config vars are required by the program in order to do anything useful.
They are guaranteed to exist later and can safely be read with |forceEither $
get|.

> requiredConfigVars :: [String]
> requiredConfigVars = [  "authtokensalt", "articledir", "staticdir",
>                         "supportaddress" ]

This retrieves the config file and makes sure that it contains all of the
required configuration variables. We check the variables now because we want to
find out about missing ones at program start time rather than in the logs
later.

> getConfig :: IO (Either CPError ConfigParser)
> getConfig = runErrorT $ do
>   cp <- join $ liftIO $ readfile emptyCP configFile
>   opts <- options cp "DEFAULT"
>   if requiredConfigVars `intersect` opts == requiredConfigVars
>      then return cp
>      else error "Missing configuration options."

|handleRequest| ``digests'' the requested URI before passing it to the
 dispatcher.

> handleRequest :: App CGIResult
> handleRequest = do
>   uri     <- requestURI
>   method  <- requestMethod
>   let path = pathList uri
>   dispatch' method path

We extract the path part of the URI, ``unescape it'' (convert % codes back to
characters), decode it (convert \mbox{UTF-8} characters to Unicode Chars), and finally
parse it into directory and filename components. For example,

\begin{quote}@/some/directory/and/a/filename@\end{quote}

becomes

\begin{quote}|["some","directory","and","a","filename"]|\end{quote}

Note that the parser does not have to deal with query strings or fragments
because |uriPath| has already stripped them.

The one case this doesn't handle correctly is @//something@, because it's
handled differently by |Network.CGI|.

> pathList :: URI -> [String]
> pathList = splitOn "/" . decodeString . unEscapeString . uriPath

Before we actually dispatch the request, we use the opportunity to clean up the
URI and redirect the client if necessary. This handles cases like trailing
slashes. We want only one URI to point to a resource.\footnote{I'm not sure
that this is the right thing to do. Would it be better just to give the client
a 404?}

> dispatch' :: String -> [String] -> App CGIResult
> dispatch' method path =
>   case path of
>     ["",""]  -> frontPage -- "/"
>     ("":xs)  -> case find (== "") xs of
>                   Nothing  -> dispatch method xs
>                   Just _   -> redirect $ "/" ++ (intercalate "/" $ filter (/= "") xs)
>     _        -> output404 path

Here is where we dispatch each request to a function. We can match the request
on method and path components. This means that we can dispatch a @GET@ request
to one function and a @POST@ request to another.

> dispatch :: String -> [String] -> App CGIResult

\subsection{Articles}

Some permanent URIs are essentially static files. To display them, we make use
of the article system (formatting, metadata, etc). You could call these elevated
articles. We use articles because the system for managing them exists already
(revision control, etc)

Each @.html@ file is actually an HTML fragment. These happen to be generated
from Muse Mode files by Emacs, but we don't really care where they come from.

> dispatch "GET" ["help"]          =  articlePage "help"
> dispatch "GET" ["privacy"]       =  articlePage "privacy"
> dispatch "GET" ["terms-of-use"]  =  articlePage "terms-of-use"
> dispatch "GET" ["source"]        =  articlePage "source"

Other articles are dynamic and can be created without recompilation. We just
have to rescan the filesystem for them. They also live in the @/article@
namespace (specifically at @/article/title@).

> dispatch "GET" ["article",x] = articlePage x

We have 1 page for getting a listing of all published articles.

> dispatch "GET"   ["articles"] = articlesPage

And this is a method used by the web-based administrative interface to reload
the articles from the filesystem. (Articles are transmitted to the server via
rsync using the filesystem, not through the web.)

> dispatch "POST"  ["articles"] = refreshArticles

\subsection{Link Pages}

Vocabulink revolves around links---the associations between words or ideas. As
with articles, we have different functions for retrieving a single link or a
listing of links. However, the dispatching is complicated by the fact that
members can operate upon links (we need to handle the @POST@ method).

If we could rely on the @DELETE@ method being supported by all browsers, this
would be a little less ugly. However, I've decided to only use @GET@ and
@POST@. All other methods are appended as an extra path component (here, as
|method'|).\footnote{I'm not 100\% satisfied with this design decision, but I
haven't thought of a better way yet.}

For clarity, this dispatches:

\begin{center}
\begin{tabular}{lcl}
@GET  /link/new@          & $\rightarrow$ & form to create a new link \\
@POST /link/new@          & $\rightarrow$ & create a new link \\
@GET  /link/10@           & $\rightarrow$ & link page \\
@GET  /link/something@    & $\rightarrow$ & not found \\
@GET  /link/10/something@ & $\rightarrow$ & not found \\
@POST /link/10/delete@    & $\rightarrow$ & delete link
\end{tabular}
\end{center}

Creating a new link is a 2-step process. First, the member requests a page
on which to enter information about the link. Then they @POST@ the details to
establish the link. (Previewing is done through the @GET@ as well.)

> dispatch "GET"   ["link","new"] = newLink
> dispatch "POST"  ["link","new"] = newLink

> dispatch method path@("link":x:method') = do
>   case maybeRead x of
>     Nothing  -> output404 path
>     Just n   -> case (method, method') of
>                   ("GET"   ,[])          -> linkPage n
>                   ("POST"  ,["delete"])  -> deleteLink n
>                   (_       ,_)           -> output404 path

\subsection{Searching}

Retrieving a listing of links is easier.

Searching means forms and forms mean query strings. So if there's a @contains@
in the query string for the links page, it will do a search. E.g.

\begin{center}
@GET /links?contains=water@
\end{center}

> dispatch "GET" path@["links"] = do
>   contains <- getInput "contains"
>   ol <- getInput "ol"
>   dl <- getInput "dl"
>   case (contains, ol, dl) of
>     (Just contains', _, _)   -> linksContainingPage contains'
>     (_, Just ol', Just dl')  -> do
>       ol'' <- languageNameFromAbbreviation ol'
>       dl'' <- languageNameFromAbbreviation dl'
>       case (ol'', dl'') of
>         (Just ol''', Just dl''')  -> linksPage  ("Links from " ++ ol''' ++ " to " ++ dl''')
>                                                 (languagePairLinks ol' dl')
>         _                         -> output404 path
>     _                        -> linksPage "Latest Links" latestLinks
> dispatch "GET" path@["links",x] = do
>   case maybeRead x of
>     Nothing  -> output404 path
>     Just n   -> do
>       memberName <- getMemberName n
>       case memberName of
>         Nothing  -> output404 path
>         Just n'  -> linksPage ("Links by " ++ n') (memberLinks n)

\subsection{Link Packs}

The process of creating link packs is similar to that for creating links.

> dispatch "GET"   ["packs"] = linkPacksPage

> dispatch "GET"   ["pack","new"] = newLinkPack
> dispatch "POST"  ["pack","new"] = newLinkPack

> dispatch "POST"  ["pack","image"] = uploadFile "/pack/image"

> dispatch "POST"  ["pack","link","new"] = addToLinkPack

> dispatch method path@("pack":x:method') = do
>   case maybeRead x of
>     Nothing  -> output404 path
>     Just n   -> case (method, method') of
>                   ("GET"   ,[])          -> linkPackPage n
>                   ("POST"  ,["delete"])  -> deleteLinkPack n
>                   (_       ,_)           -> output404 path

\subsection{Languages}

Browsing through every link on the site doesn't work with a significant number
of links. A languages page shows what's available and contains hyperlinks to
language-specific browsing.

> dispatch "GET"  ["languages"] = languagePairsPage

\subsection{Link Review}

Members review their links by interacting with the site in a vaguely REST-ish
way. The intent behind this is that in the future they will be able to review
their links through different means such as a desktop program or a phone
application.

Because of the use of |withRequiredMemberNumber|, a logged out member will be
redirected to a login page when attempting to review.

\begin{center}
\begin{tabular}{lcl}
retrieve the next link for review & $\rightarrow$ & @GET  /review/next@ \\
mark link as reviewed             & $\rightarrow$ & @POST /review/n@ \\
add a link for review             & $\rightarrow$ & @POST /review/n/add@
\end{tabular}
\end{center}

(where @n@ is the link number)

> dispatch method path@("review":rpath) =
>   withRequiredMemberNumber $ \memberNo ->
>     case (method,rpath) of
>       ("GET"   ,["next"])   -> nextReview memberNo
>       ("POST"  ,(x:xs))     -> do
>          case maybeRead x of
>            Nothing  -> outputError 400
>                        "Links are identified by numbers only." []
>            Just n   -> case xs of
>                          ["add"]  -> newReview memberNo n
>                          []       -> linkReviewed memberNo n
>                          _        -> output404 path
>       (_       ,_)          -> output404 path

\subsection{Membership}

Becoming a member is simply a matter of filling out a form.

> dispatch "GET"   ["member","signup"]  = registerMember
> dispatch "POST"  ["member","signup"]  = registerMember

But to use most of the site, we require email confirmation.

> dispatch "GET"   ["member","confirmation"]    = confirmEmailPage
> dispatch "GET"   ["member","confirmation",x]  = confirmEmail x

Logging in is a similar process.

> dispatch "GET"   ["member","login"]  = login
> dispatch "POST"  ["member","login"]  = login

Logging out can be done without a form.

> dispatch "POST"  ["member","logout"]  = logout

Members can also request support, if for some reason they can't or don't want
to use the forums.

> dispatch "GET"   ["member","support"]  = memberSupport
> dispatch "POST"  ["member","support"]  = memberSupport

\subsection{Forums}

While Vocabulink is still growing (and into the future), it's important to help
new members along and to get feedback from them. For this, Vocabulink uses
forums.

You may begin to notice a dispatching pattern by now.

> dispatch "GET"   ["forums"] = forumsPage
> dispatch "POST"  ["forums"] = forumsPage

Forums are uniquely identified by their name. The names are trusted to be
unique and reversibly mappable into URI-safe strings because they are created
by administrators of the site.

> dispatch "POST"  ["forum","new"] = createForum
> dispatch "GET"   ["forum",x] = forumPage x

However, topics can be created by anyone and are identified by numbers. This
might seem like a lost opportunity for search engine optimization, but
including the forum topic text could lead to some very long URIs.

> dispatch "GET"   ["forum",x,"new"] = newTopicPage x
> dispatch "POST"  ["forum",x,"new"] = newTopicPage x

> dispatch "GET"   path@["forum",x,y] =
>   case maybeRead y of
>     Nothing  -> output404 path
>     Just n   -> forumTopicPage x n

``reply'' and ``preview'' are used here as nouns.

> dispatch "GET"   ["comment","reply"] = replyToComment
> dispatch "POST"  ["comment","reply"] = replyToComment

> dispatch "GET"   ["comment","preview"] = commentPreview

\subsection{Everything Else}

For Google Webmaster Tools, we need to respond to a certain URI that acts as a
kind of ``yes, we really do run this site''.

> dispatch "GET" ["google46b9909165f12901.html"] = output' ""

It would be nice to automatically respond with ``Method Not Allowed'' on URIs
that exist but don't make sense for the requested method (presumably @POST@).
However, we need to take a simpler approach because of how the dispatch method
was designed (pattern matching is limited). We output a qualified 404 error.

> dispatch _ path = output404 path

Finally, we get to an actual page of the site: the front page. Currently, it's
doing a lot more than I'd like it to do. But it'll have to stay this way until
we have some sort of widget/layout system. It gets the common header, footer,
and associated functionality by using the |stdPage| function.

Logged-in members are presented with a different ``article'' in the main body
as well as a ``My Links'' box showing them the links that they've created. The
page also shows a list of recent articles should the reader feel a little lost
or curious.

> frontPage :: App CGIResult
> frontPage = do
>   memberNo <- asks appMemberNo
>   my <- maybe (return noHtml) (myLinks) memberNo
>   latest <- newLinks
>   articles <- latestArticles
>   featured <- featuredPack
>   let article = isJust memberNo ? "welcome-member" $ "welcome"
>   article' <- getArticle article
>   body <- maybe (return $ h1 << "Welcome to Vocabulink") articleBody article'
>   stdPage "Welcome to Vocabulink" [JS "MochiKit", JS "page"] [] [
>     thediv ! [identifier "main-content"] << body,
>     thediv ! [identifier "sidebar"] << [
>       featured, latest, my, articles ] ]
>  where myLinks mn = do
>          ls <- memberLinks mn 0 10
>          case ls of
>            Nothing   -> return noHtml
>            Just ls'  -> do
>              partialLinks <- mapM partialLinkHtml ls'
>              return $ thediv ! [theclass "sidebox"] << [
>                         h3 << anchor ! [href ("/links/" ++ (show mn))] <<
>                           "My Links",
>                         unordList partialLinks ! [theclass "links"] ]
>        newLinks = do
>          ls <- latestLinks 0 10
>          case ls of
>            Nothing   -> return noHtml
>            Just ls'  -> do
>              partialLinks <- mapM partialLinkHtml ls'
>              return $ thediv ! [theclass "sidebox"] << [
>                         h3 << anchor ! [href "/links"] <<
>                           "Latest Links",
>                         unordList partialLinks ! [theclass "links"] ]
>        latestArticles = do
>          ls <- getArticles
>          return $ maybe (noHtml) (\l -> thediv ! [theclass "sidebox"] << [
>                                           h3 << anchor ! [href "/articles"] <<
>                                             "Latest Articles",
>                                           unordList (map articleLinkHtml l)]) ls
>        featuredPack = do
>          lp <- getLinkPack 1
>          return $ maybe (noHtml) (\l -> thediv ! [theclass "sidebox"] << [
>                                           h3 << [  stringToHtml "Featured Link Pack:", br,
>                                                    linkPackTextLink l ],
>                                           displayCompactLinkPack l False ]) lp

%include Vocabulink/Utils.lhs
%include Vocabulink/CGI.lhs
%include Vocabulink/App.lhs
%include Vocabulink/DB.lhs
%include Vocabulink/Html.lhs
%include Vocabulink/Member/AuthToken.lhs
%include Vocabulink/Member.lhs
%include Vocabulink/Link.lhs
%include Vocabulink/Review.lhs
%include Vocabulink/Review/Html.lhs
%include Vocabulink/Review/SM2.lhs
%include Vocabulink/Article.lhs
%include Vocabulink/Forum.lhs

That's it! You've seen everything required to run
\url{http://www.vocabulink.com/}!

\end{document}