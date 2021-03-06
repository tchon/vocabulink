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

-- | System-level metrics (not individual)

module Vocabulink.Metrics (metricsPage, dateSeriesChart) where

import Vocabulink.App
import Vocabulink.CGI
import Vocabulink.Html
import Vocabulink.Page
import Vocabulink.Utils

import Prelude hiding (div, id, span)

-- | Display various high-level system metrics.
metricsPage :: App CGIResult
metricsPage = do
  today <- liftIO currentDay
  let start = addDays (-30) today
      end   = today
  signups  <- signupCounts start end
  links    <- linkCounts start end
  stories  <- storyCounts start end
  comments <- commentCounts start end
  reviews  <- reviewCounts start end
  simplePage "Metrics" [JS "raphael", JS "metrics", CSS "metrics"] $ do
    h2 "Sign Ups"
    dateSeriesChart signups
      ! customAttribute "start" (stringValue $ showGregorian start)
      ! customAttribute "end"   (stringValue $ showGregorian end)
    h2 "Reviews"
    dateSeriesChart reviews
      ! customAttribute "start" (stringValue $ showGregorian start)
      ! customAttribute "end"   (stringValue $ showGregorian end)
    h2 "Links"
    dateSeriesChart links
      ! customAttribute "start" (stringValue $ showGregorian start)
      ! customAttribute "end"   (stringValue $ showGregorian end)
    h2 "Stories"
    dateSeriesChart stories
      ! customAttribute "start" (stringValue $ showGregorian start)
      ! customAttribute "end"   (stringValue $ showGregorian end)
    h2 "Comments"
    dateSeriesChart comments
      ! customAttribute "start" (stringValue $ showGregorian start)
      ! customAttribute "end"   (stringValue $ showGregorian end)

dateSeriesChart :: [(Day, Integer)] -> Html
dateSeriesChart data' =
  table ! class_ "date-series" $ do
    thead $ tr $ do
      th "Date"
      th "Value"
    tbody $ mconcat $ map row data'
 where row datum = tr $ do
                     td $ string $ show $ fst datum
                     td $ string $ show $ snd datum

-- | # of signups each day in a given date range
signupCounts :: Day -- ^ start date
             -> Day -- ^ end date
             -> App [(Day, Integer)] -- ^ counts for each date
signupCounts start end = (fromJust *** fromJust) <$$> $(queryTuples'
  "SELECT CAST(join_date AS date), COUNT(*) FROM member \
  \WHERE CAST(join_date AS date) BETWEEN {start} AND {end} \
  \GROUP BY CAST(join_date AS date) \
  \ORDER BY join_date")

linkCounts :: Day -- ^ start date
           -> Day -- ^ end date
           -> App [(Day, Integer)] -- ^ counts for each date
linkCounts start end = (fromJust *** fromJust) <$$> $(queryTuples'
  "SELECT CAST(created AS date), COUNT(*) FROM link \
  \WHERE CAST(created AS date) BETWEEN {start} AND {end} \
  \GROUP BY CAST(created AS date) \
  \ORDER BY created")

storyCounts :: Day -- ^ start date
            -> Day -- ^ end date
            -> App [(Day, Integer)] -- ^ counts for each date
storyCounts start end = (fromJust *** fromJust) <$$> $(queryTuples'
  "SELECT CAST(created AS date), COUNT(*) FROM linkword_story \
  \WHERE CAST(created AS date) BETWEEN {start} AND {end} \
  \GROUP BY CAST(created AS date) \
  \ORDER BY created")

commentCounts :: Day -- ^ start date
              -> Day -- ^ end date
              -> App [(Day, Integer)] -- ^ counts for each date
commentCounts start end = (fromJust *** fromJust) <$$> $(queryTuples'
  "SELECT CAST(time AS date), COUNT(*) FROM comment \
  \WHERE author <> 0 AND CAST(time AS date) BETWEEN {start} AND {end} \
  \GROUP BY CAST(time AS date) \
  \ORDER BY time")

reviewCounts :: Day -- ^ start date
             -> Day -- ^ end date
             -> App [(Day, Integer)] -- ^ counts for each date
reviewCounts start end = (fromJust *** fromJust) <$$> $(queryTuples'
  "SELECT CAST(actual_time AS date), COUNT(*) FROM link_review \
  \WHERE CAST(actual_time AS date) BETWEEN {start} AND {end} \
  \GROUP BY CAST(actual_time AS date) \
  \ORDER BY actual_time")
