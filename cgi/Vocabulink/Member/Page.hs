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

-- | Member Page

module Vocabulink.Member.Page (memberPage) where

import Vocabulink.App
import Vocabulink.CGI
import Vocabulink.Html
import Vocabulink.Link
import Vocabulink.Link.Html
import Vocabulink.Member
import Vocabulink.Page
import Vocabulink.Utils

import Prelude hiding (div, span, id)

memberPage :: String -> App CGIResult
memberPage username = do
  member <- memberByName username
  isSelf <- maybe False (\ m -> memberName m == username) <$> asks appMember
  case member of
    Nothing -> outputNotFound
    Just m  -> do
      let avatar = fromMaybe mempty (memberAvatar 60 m)
      links <- mapM renderPartialLink =<< memberLinks (memberNumber m) 0 10
      stories <- latestStories m
      stdPage (memberName m ++ "'s Vocabulink Page") [CSS "member-page", CSS "link"] mempty $ do
        div ! id "avatar" $ do
          avatar
          span ! class_ "username" $ string $ memberName m
          when isSelf $ do br
                           span $ do string "Change your avatar at "
                                     a ! href "http://gravatar.com" $ "gravatar.com"
        multiColumn
          [div $ do
             h2 $ string ("Latest Links by " ++ memberName m)
             unordList links ! class_ "links",
           div $ do
             h2 $ string ("Latest Stories by " ++ memberName m)
             case stories of
               [] -> string "no stories"
               _  -> unordList stories ! class_ "stories"]

latestStories :: Member -> App [Html]
latestStories m = map renderStory <$> $(queryTuples'
  "SELECT story_no, link_no, story FROM linkword_story \
  \WHERE author = {memberNumber m} \
  \ORDER BY edited DESC LIMIT 5")
 where renderStory (sn, ln, s) = a ! href (stringValue $ "/link/" ++ show ln ++ "#" ++ show sn)
                                   $ markdownToHtml s