-- Copyright 2011 Chris Forno

-- This file is part of Vocabulink.

-- Vocabulink is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Affero General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option)
-- any later version.

-- Vocabulink is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
-- for more details.

-- You should have received a copy of the GNU Affero General Public License
-- along with Vocabulink. If not, see <http://www.gnu.org/licenses/>.

module Vocabulink.Link.Html ( newLinkPage, linkPage, linksPage, languagePairsPage
                            , renderLink, renderPartialLink, partialLinksTable
                            , wordCloud
                            ) where

import Vocabulink.App
import Vocabulink.CGI
import Vocabulink.Comment
import Vocabulink.Html
import Vocabulink.Link
import Vocabulink.Link.Pronunciation
import Vocabulink.Link.Story
import Vocabulink.Member
import Vocabulink.Page
import Vocabulink.Utils

import Control.Monad.State (State, runState, get, put)
import Data.List (find, genericLength, sortBy, groupBy)
import System.Random
import Text.Blaze.Html5 (audio, source)
import Text.Blaze.Html5.Attributes (preload)

import Prelude hiding (div, span, id, words)

newLinkPage :: App CGIResult
newLinkPage = do
  foreignLangs  <- languageMenu $ Left ()
  familiarLangs <- languageMenu $ Right ()
  foreignWord <- getInputDefault "" "foreign"
  simplePage "Create a New Link" [CSS "lib.link", JS "link"] $ do
    form ! method "post" ! action "/link/new" $ do
      h1 ! class_ "link edit linkword" $ do
        span ! class_ "foreign" $ do
          input ! name "foreign" ! required mempty ! placeholder "Foreign Word" ! tabindex "1" ! value (stringValue foreignWord)
          br
          foreignLangs ! name "foreign-lang" ! required mempty
        span ! class_ "link" $ do
          input ! name "linkword" ! required mempty ! placeholder "Link Word" ! tabindex "2"
          br
          menu (zip activeLinkTypes activeLinkTypes) ! name "link-type" ! required mempty
        span ! class_ "familiar" $ do
          input ! name "familiar" ! required mempty ! placeholder "Translation" ! tabindex "3"
          br
          familiarLangs ! name "familiar-lang" ! required mempty
      p ! style "text-align: center" $
        input ! type_ "submit" ! class_ "light" ! value "Save" ! tabindex "4"

-- Each link gets its own URI and page. Most of the extra code in the following is
-- for handling the display of link operations (``review'', ``delete'', etc.),
-- dealing with retrieval exceptions, etc.

-- For the link's owner, we'll send along the source of the link in a hidden
-- textarea for in-page editing.

linkPage :: Integer -> App CGIResult
linkPage linkNo = do
  memberNo <- memberNumber <$$> asks appMember
  l <- getLink linkNo
  case l of
    Nothing -> outputNotFound
    Just l' -> do
      viewable <- canView l'
      if not viewable
        then outputNotFound
        else do
          let owner' = maybe False (linkAuthor l' ==) memberNo
          ops <- linkOperations l'
          hasPronunciation <- pronounceable linkNo
          foLang <- linkForeignLanguage l'
          faLang <- linkFamiliarLanguage l'
          let fo = linkForeignPhrase l'
              fa = linkFamiliarPhrase l'
          row <- $(queryTuple' "SELECT root_comment \
                               \FROM link_comment \
                               \WHERE link_no = {linkNo}")
          comments <- case row of
                        Just root  -> renderComments root
                        Nothing    -> return mempty
          renderedLink <- renderLink l' hasPronunciation
          -- Only worry about 1 listed frequency for now.
          rank <- $(queryTuple' "SELECT MIN(rank) \
                                \FROM link_frequency \
                                \WHERE link_no = {linkNo}")
          stories <- if isLinkword l'
                       then do
                         ss <- linkWordStories (linkNumber l')
                         return $ mconcat $ map (\ (n, x, y, z) -> renderStory n x y z) ss
                       else return mempty
          stdPage (fo ++ " → " ++ fa ++ " — " ++ foLang ++ " to " ++ faLang) [CSS "lib.link", JS "link"] mempty $ do
            div ! id "link-head-bar" $ do
              h2 $ a ! href (stringValue $ "/links?ol=" ++ linkForeignLang l' ++ "&dl=" ++ linkFamiliarLang l') $
                string (foLang ++ " to " ++ faLang ++ ":")
              div ! id "link-ops" $ do
                span ! id "rank" $ do
                  case fromJust rank of
                    Just r  -> string $ "Rank: " ++ show r
                    Nothing -> if memberNo == Just 1 || memberNo == Just 2
                                 then string "Rank: ?"
                                 else mempty
                ops
            renderedLink
            when (isLinkword l') $
              div ! id "linkword-stories" $ do
                div ! class_ "header" $ h2 "Linkword Stories:"
                stories
            clear
            div ! id "comments" $ do
              h3 "Comments"
              comments

linksPage :: String -> [(PartialLink, Maybe Integer, Bool)] -> App CGIResult
linksPage title' links = do
  simplePage title' [JS "link", CSS "lib.link", ReadyJS initJS] $ do
    partialLinksTable links
 where initJS = unlines
                  ["var startPage = 1;"
                  ,"var pageHash = /^#page(\\d+)$/.exec(window.location.hash);"
                  ,"if (pageHash) {"
                  ,"  startPage = parseInt(pageHash[1], 10);"
                  ,"}"
                  ,"$('table').longtable().bind('longtable.pageChange', function (_, n) {"
                  ,"  window.location.hash = 'page' + n;"
                  ,"}).gotoPage(startPage);"
                  ]

partialLinksTable :: [(PartialLink, Maybe Integer, Bool)] -> Html
partialLinksTable links = table ! class_ "links" $ do
  thead $ do
    tr $ do
      th "Foreign"
      th "Familiar"
      th "Link Type"
      th "Reviewing"
      th "Rank"
  tbody $ mconcat $ map linkRow links
 where linkRow (link, rank, reviewing) = let url = "/link/" ++ show (linkNumber $ pLink link) in
         tr ! class_ (stringValue $ "partial-link " ++ (linkTypeName $ pLink link)) $ do
           td $ a ! href (stringValue url) $ string $ linkForeignPhrase $ pLink link
           td $ a ! href (stringValue url) $ string $ linkFamiliarPhrase $ pLink link
           td $ a ! href (stringValue url) $ string $ linkTypeName $ pLink link
           td $ a ! href (stringValue url) ! class_ (stringValue (reviewing ? "reviewing" $ "")) $ string (reviewing ? "yes" $ "no")
           td $ a ! href (stringValue url) $ string $ maybe "" show rank

languagePairsPage :: App CGIResult
languagePairsPage = do
  languages' <- (groupBy groupByName . sortBy compareNames) <$> linkLanguages
  simplePage "Links By Language" [CSS "lib.link"] $ do
    mconcat $ map renderLanguageGroup $ sortBy compareSize languages'
 where compareNames ((_, ol1), (_, dl1), _) ((_, ol2), (_, dl2), _) =
         if dl1 == dl2
            then compare ol1 ol2
            else compare dl1 dl2
       compareSize g1 g2 = compare (languageSize g2) (languageSize g1)
       languageSize = sum . map (\(_, _, c) -> c)
       groupByName ((_, _), (_, dl1), _) ((_, _), (_, dl2), _) = dl1 == dl2
       renderLanguageGroup g = div ! class_ "group-box languages" $ do
         h2 $ string $ "in " ++ (groupLanguage g) ++ ":"
         multiColumnList 3 $ map renderLanguage g
       groupLanguage = (\((_, _), (_, n), _) -> n) . head
       renderLanguage ((oa, on), (da, _), _) =
         a ! class_ "faint-gradient-button blue language-button" ! href (stringValue $ "/links?ol=" ++ oa ++ "&dl=" ++ da) $
           string $ on

linkOperations :: Link -> App Html
linkOperations link = do
  member <- asks appMember
  deletable  <- canDelete link
  reviewing' <- reviewing link
  let review  = linkAction "add to review" "add"
  return $ do
    case (member, reviewing') of
      (_,       True) -> review False ! title "already reviewing this link"
      (Just _,  _)    -> review True  ! id "link-op-review"
                                      ! title "add this link to be quizzed on it later"
      (Nothing, _)    -> review False ! title "login to review"
    when deletable $ linkAction "delete link" "delete" True
                       ! id "link-op-delete"
                       ! title "delete this link (it will still be visibles to others who are reviewing it)"
 where reviewing :: Link -> App Bool
       reviewing l = do
         member <- asks appMember
         case member of
           Nothing -> return False
           Just m  -> (/= []) <$> $(queryTuples'
             "SELECT link_no FROM link_to_review \
             \WHERE member_no = {memberNumber m} AND link_no = {linkNumber l} \
             \LIMIT 1")

-- Each lexeme needs to be annotated with its language (to aid with
-- disambiguation, searching, and sorting). Most members are going to be
-- studying a single language, and it would be cruel to make them scroll
-- through a huge list of languages each time they wanted to create a new link.
-- So what we do is sort languages that the member has already used to the top
-- of the list (based on frequency).

-- This takes an either parameter to signify whether you want foreign language
-- (Left) or familiar language (Right). They are sorted separately.

languageMenu :: Either () () -> App Html
languageMenu side = do
  member <- asks appMember
  allLangs <- asks appLanguages
  langs <- case member of
    Nothing -> return []
    Just m  -> case side of
      Left  _ -> $(queryTuples'
        "SELECT abbr, name \
        \FROM link, language \
        \WHERE language.abbr = link.foreign_language \
          \AND link.author = {memberNumber m} \
        \GROUP BY foreign_language, abbr, name \
        \ORDER BY MAX(created) DESC")
      Right _ -> $(queryTuples'
        "SELECT abbr, name \
        \FROM link, language \
        \WHERE language.abbr = link.familiar_language \
          \AND link.author = {memberNumber m} \
        \GROUP BY familiar_language, abbr, name \
        \ORDER BY MAX(created) DESC")
  -- Default to English as the familiar language to make things easier and more
  -- obvious for new users.
  let langs' = case (langs, side) of
                 ([], Right _) -> [("en", "English")]
                 _             -> langs
      prompt = case side of
                 Left _  -> "Pick foreign language"
                 Right _ -> "Pick familiar language"
  return $ menu $ langs' ++ [("", prompt)] ++ allLangs

-- Displaying Links

-- <h1 class="link linkword">
--     <span class="foreign" title="Esperanto">nur</span>
--     <span class="link" title="linkword">newer</span>
--     <span class="familiar" title="English">only</span>
-- </h1>

-- <h2 class="link soundalike">
--     <span class="foreign" title="Esperanto">lingvo</span>
--     <span class="link" title="soundalike"></span>
--     <span class="familiar" title="English">language</span>
-- </h2>

-- We really shouldn't need to allow for passing class names. However, the !
-- function has a problem in that it will add another class attribute instead of
-- extending the existing one, which at least jquery doesn't like.

renderLink :: Link -> Bool -> App Html
renderLink link pronounceable' = do
  foLang <- linkForeignLanguage link
  faLang <- linkFamiliarLanguage link
  (prevLink, nextLink) <- adjacentLinkNumbers link
  return $ h1 ! class_ (stringValue $ "link " ++ linkTypeName link) $ do
    a ! href (stringValue $ show prevLink) ! class_ "prev"
      ! title (stringValue $ "Previous " ++ foLang ++ "→" ++ faLang ++ " Link") $ mempty
    span ! class_ "foreign" ! customAttribute "lang" (stringValue $ linkForeignLang link) ! title (stringValue foLang) $ do
      string $ linkForeignPhrase link
      pronunciation
    span ! class_ "link" ! title (stringValue $ linkTypeName link) $
      renderLinkType (linkType link)
    span ! class_ "familiar" ! customAttribute "lang" (stringValue $ linkFamiliarLang link) ! title (stringValue faLang) $ string $ linkFamiliarPhrase link
    a ! href (stringValue $ show nextLink) ! class_ "next"
      ! title (stringValue $ "Next " ++ foLang ++ "→" ++ faLang ++ " Link") $ mempty
 where renderLinkType :: LinkType -> Html
       renderLinkType (Linkword word) = string word
       renderLinkType _               = mempty
       pronunciation = if pronounceable'
                         then button ! id "pronounce" ! class_ "button light" $ do
                                audio ! preload "auto" $ do
                                  source ! src (stringValue $ "http://s.vocabulink.com/audio/pronunciation/" ++ show (linkNumber link) ++ ".ogg") $ mempty
                                  source ! src (stringValue $ "http://s.vocabulink.com/audio/pronunciation/" ++ show (linkNumber link) ++ ".mp3") $ mempty
                                img ! src "http://s.vocabulink.com/img/icon/audio.png"
                         else mempty

renderPartialLink :: PartialLink -> App Html
renderPartialLink (PartialLink l) = do
  foLang <- linkForeignLanguage l
  faLang <- linkFamiliarLanguage l
  return $
    a ! class_ (stringValue $ "partial-link " ++ linkTypeName l)
      ! href (stringValue $ "/link/" ++ show (linkNumber l))
      ! title (stringValue $ foLang ++ " → " ++ faLang) $ do
      span ! class_ "foreign" $ string $ linkForeignPhrase l
      string " → "
      span ! class_ "familiar" $ string $ linkFamiliarPhrase l

-- Displaying an entire link involves not just drawing a graphical
-- representation of the link but displaying its type-level details as well.

displayLink :: Link -> App Html
displayLink l = do
  renderedLink <- renderLink l False
  return $ do
    renderedLink
    div ! class_ "link-details htmlfrag" $ linkTypeHtml (linkType l)

linkTypeHtml :: LinkType -> Html
linkTypeHtml _ = mempty

-- Each link can be ``operated on''. It can be reviewed (added to the member's
-- review set) and deleted (marked as deleted). In the future, I expect
-- operations such as ``tag'', ``rate'', etc.

-- The |Bool| parameter indicates whether or not the currently logged-in member
-- (if the client is logged in) is the owner of the link.

linkAction :: String -> String -> Bool -> Html
linkAction label' icon' enabled =
  let icon = "http://s.vocabulink.com/img/icon/" ++
             icon' ++
             (enabled ? "" $ "-disabled") ++
             ".png" in
  a ! class_ (stringValue $ "operation login-required " ++ (enabled ? "enabled" $ "disabled")) ! href "" $ do
    img ! src (stringValue icon) ! class_ "icon"
    string label'

-- Generate a cloud of words from links in the database.

data WordStyle = WordStyle (Float, Float) (Float, Float) Int Int
  deriving (Show, Eq)

wordCloud :: Int -> Int -> Int -> Int -> Int -> Int -> App Html
wordCloud n width' height' fontMin fontMax numClasses = do
  words <- $(queryTuples'
    "SELECT foreign_phrase, link_no FROM link \
    \WHERE NOT deleted AND link_no IN \
     \(SELECT DISTINCT link_no FROM linkword_story) \
    \ORDER BY random() LIMIT {n}")
  gen <- liftIO getStdGen
  let (styles, (newGen, _)) = runState (mapM (wordStyle . fst) words) (gen, [])
  liftIO $ setStdGen newGen
  return $ mconcat $ catMaybes $ zipWith (\ w s -> liftM (wordTag w) s) words styles
 where wordTag :: (String, Integer) -> WordStyle -> Html
       wordTag (word, linkNo) (WordStyle (x, y) _ classNum fontSize) =
         let style' = "font-size: " ++ show fontSize ++ "px; "
                   ++ "left: " ++ show x ++ "%; " ++ "top: " ++ show y ++ "%;" in
         a ! href (stringValue $ "/link/" ++ show linkNo)
           ! class_ (stringValue $ "class-" ++ show classNum)
           ! style (stringValue style')
           $ string word
       wordStyle :: String -> State (StdGen, [WordStyle]) (Maybe WordStyle)
       wordStyle word = do
         let fontRange = fontMax - fontMin
         fontSize <- (\ s -> fontMax - round (logBase 1.15 ((s * (1.15 ^ fontRange)::Float) + 1))) <$> getRandomR 0.0 1.0
         let widthP  = (100.0 / (fromIntegral width')::Float)  * genericLength word * fromIntegral fontSize
             heightP = (100.0 / (fromIntegral height')::Float) * fromIntegral fontSize
         x        <- getRandomR 0 (max (100 - widthP) 1)
         y        <- getRandomR 0 (max (100 - heightP) 1)
         class'   <- getRandomR 1 numClasses
         (gen, prev) <- get
         let spiral' = spiral 30.0 (x, y)
             styles  = filter inBounds $ map (\ pos -> WordStyle pos (widthP, heightP) class' fontSize) spiral'
             style'  = find (\ s -> not $ any (`overlap` s) prev) styles
         case style' of
           Nothing -> return Nothing
           Just style'' -> do
             put (gen, style'':prev)
             return $ Just style''
       getRandomR :: Random a => a -> a -> State (StdGen, [WordStyle]) a
       getRandomR min' max' = do
         (gen, styles) <- get
         let (n', newGen) = randomR (min', max') gen
         put (newGen, styles)
         return n'
       inBounds :: WordStyle -> Bool
       inBounds (WordStyle (x, y) (w, h) _ _) = x >= 0 && y >= 0 && x + w <= 100 && y + h <= 100
       overlap :: WordStyle -> WordStyle -> Bool
       -- We can't really be certain of when a word is overlapping,
       -- since the words will be rendered by the user's browser.
       -- However, we can make a guess.
       overlap (WordStyle (x1, y1) (w1', h1') _ _) (WordStyle (x2, y2) (w2', h2') _ _) =
         let hInter = (x2 > x1 && x2 < x1 + w1') || (x2 + w2' > x1 && x2 + w2' < x1 + w1') || (x2 < x1 && x2 + w2' > x1 + w1')
             vInter = (y2 > y1 && y2 < y1 + h1') || (y2 + h2' > y1 && y2 + h2' < y1 + h1') || (y2 < y1 && y2 + h2' > y1 + h1') in
         hInter && vInter
       spiral :: Float -> (Float, Float) -> [(Float, Float)]
       spiral maxTheta = spiral' 0.0
        where spiral' theta (x, y) =
                if theta > maxTheta
                  then []
                  else let r  = theta * 3
                           x' = (r * cos theta) + x
                           y' = (r * sin theta) + y in
                       (x', y') : spiral' (theta + 0.1) (x, y)
