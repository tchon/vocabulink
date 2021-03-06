-- Copyright 2008, 2009, 2010, 2011 Chris Forno

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

-- To register a new member we need their desired username, a password, and
-- optionally an email address.

module Vocabulink.Member.Registration ( usernameAvailable, emailAvailable
                                      , signup, confirmEmail, resendConfirmEmail
                                      , login, logout
                                      , sendPasswordReset, passwordResetPage, passwordReset
                                      ) where

import Vocabulink.App
import Vocabulink.CGI
import Vocabulink.Html
import Vocabulink.Member
import Vocabulink.Member.Auth
import Vocabulink.Page
import Vocabulink.Utils

import Prelude hiding (div, id, span)
import Network.URI (parseURI, query)

-- Once a user registers, they can log in. However, they won't be able to use
-- most member-specific functions until they've confirmed their email address.
-- This is to make sure that people cannot impersonate or spam others.

-- Email confirmation consists of generating a unique random string and
-- emailing it to the member as a hyperlink. Once they click the hyperlink we
-- consider the email address confirmed.

signup :: App CGIResult
signup = do
  member <- asks appMember
  case member of
    Just _  -> error "You're already logged in."
    _       -> do
      username' <- getRequiredInput "username"
      email'    <- getRequiredInput "email"
      password' <- getRequiredInput "password"
      terms'    <- getInput "terms"
      userAvail <- usernameAvailable username'
      emailAvail <- emailAvailable email'
      when (not userAvail) $ error "The username you chose is unavailable or invalid."
      when (not emailAvail) $ error "The email address you gave is unavailable or invalid."
      when (isNothing terms') $ error "You must accept the Terms of Use."
      memberNo <- withConnection $ \c -> do
        withTransaction c $ do
          memberNo' <- fromJust <$> $(queryTuple
                                      "INSERT INTO member (username, password_hash) \
                                      \VALUES ({username'}, crypt({password'}, gen_salt('bf'))) \
                                      \RETURNING member_no") c
          hash <- fromJust <$> $(queryTuple
                                 "INSERT INTO member_confirmation (member_no, hash, email) \
                                 \VALUES ({memberNo'}, md5(random()::text), {email'}) \
                                 \RETURNING hash") c
          res <- liftIO $ sendConfirmationEmail email' username' hash
          maybe (rollback c >> return Nothing)
                (\_ -> do $(execute "UPDATE member_confirmation \
                                    \SET email_sent = current_timestamp \
                                    \WHERE member_no = {memberNo'}") c
                          return (Just memberNo')) res
      case memberNo of
        Just mn -> do ip <- remoteAddr
                      key <- fromJust <$> getOption "authtokenkey"
                      authTok <- liftIO $ authToken mn username' ip key
                      setAuthCookie authTok
                      redirect "http://www.vocabulink.com/?signedup"
        Nothing -> error "Registration failure (this is not your fault). Please try again later."

sendConfirmationEmail :: String -> String -> String -> IO (Maybe ())
sendConfirmationEmail email username hash =
  let body = unlines ["Welcome to Vocabulink, " ++ username ++ "."
                     ,""
                     ,"Please click http://www.vocabulink.com/member/confirmation/" ++
                      hash ++ " to confirm your email address."
                     ] in
  sendMail email "Please confirm your email address." body

resendConfirmEmail :: App CGIResult
resendConfirmEmail = do
  member <- asks appMember
  case member of
    Nothing -> do
      simplePage "Please Login to Resend Your Confirmation Email"
        [ReadyJS "V.loginPopup();"] mempty
    Just m  -> do
      (hash, email) <- fromJust <$> $(queryTuple'
                         "SELECT hash, email FROM member_confirmation \
                         \WHERE member_no = {memberNumber m}")
      res <- liftIO $ sendConfirmationEmail email (memberName m) hash
      case res of
        Nothing -> error "Error sending confirmation email."
        Just _  -> simplePage "Your confirmation email has been sent." mempty mempty

-- To login a member, simply set their auth cookie. Reloading the page and such
-- is handled by the client.

login :: App CGIResult
login = do
  username' <- getRequiredInput "username"
  password' <- getRequiredInput "password"
  match <- $(queryTuple' "SELECT password_hash = crypt({password'}, password_hash) \
                         \FROM member WHERE username = {username'}")
  case match of
    Just (Just True) -> do
      ip      <- remoteAddr
      member' <- memberByName username'
      case member' of
        Nothing     -> error "Failed to lookup username."
        Just member -> do
          key <- fromJust <$> getOption "authtokenkey"
          authTok <- liftIO $ authToken (memberNumber member) username' ip key
          setAuthCookie authTok
          redirect =<< referrerOrVocabulink
    _         -> do -- error "Username and password do not match (or don't exist)."
      uri' <- parseURI <$> referrerOrVocabulink
      case uri' of
        Just uri -> let query' = case query uri of
                                   "" -> "?badlogin"
                                   q' -> "?" ++ q' ++ "&badlogin" in
                    redirect $ show $ uri {uriQuery = query'}
        Nothing  -> redirect "http://www.vocabulink.com/?badlogin"

-- To logout a member, we simply clear their auth cookie and redirect them
-- to the front page.

logout :: App CGIResult
logout = do
  deleteAuthCookie
  redirect "http://www.vocabulink.com/"

-- We could attempt to check username availability by looking for a user's
-- page. However, a 404 does not necessarily indicate that a username is
-- available:
-- 1. The username might be invalid.
-- 2. The page might be hidden.
-- 3. The casing might be different.
usernameAvailable :: String -> App Bool
usernameAvailable u =
  if' (length u < 4)  (return False) $
  if' (length u > 24) (return False) $
  isNothing <$> $(queryTuple' "SELECT username FROM member \
                              \WHERE username ILIKE {u}")

-- TODO: Validate email addresses.
emailAvailable :: String -> App Bool
emailAvailable e =
  isNothing <$> $(queryTuple' "(SELECT email FROM member \
                               \WHERE email ILIKE {e}) \
                              \UNION \
                              \(SELECT email FROM member_confirmation \
                               \WHERE email ILIKE {e})")

-- This is the place that the dispatcher will send the client to if they click
-- the hyperlink in the email. If confirmation is successful it redirects them
-- to some hopefully useful page.

-- Once we have confirmed the member's email, we need to set a new auth token
-- cookie for them that contains their gravatar hash.

confirmEmail :: String -> App CGIResult
confirmEmail hash = do
  member <- asks appMember
  when (isJust (memberEmail =<< member)) $ error "You've already confirmed your email."
  case member of
    Nothing -> do
      simplePage "Please Login to Confirm Your Account"
        [ReadyJS "V.loginPopup();"] mempty
    Just m  -> do
      match <- maybe False fromJust <$> $(queryTuple'
        "SELECT hash = {hash} FROM member_confirmation \
        \WHERE member_no = {memberNumber m}")
      if match
        then do h <- asks appDB
                liftIO $ withTransaction h $ do
                  $(execute "UPDATE member SET email = \
                             \(SELECT email FROM member_confirmation \
                              \WHERE member_no = {memberNumber m}) \
                            \WHERE member_no = {memberNumber m}") h
                  $(execute "DELETE FROM member_confirmation \
                            \WHERE member_no = {memberNumber m}") h
                -- We can't just look at the App's member object, since we just
                -- updated it.
                -- TODO: The logic isn't quite right on this.
                ip <- remoteAddr
                key <- fromJust <$> getOption "authtokenkey"
                authTok <- liftIO $ authToken (memberNumber m) (memberName m) ip key
                setAuthCookie authTok
                redirect "http://www.vocabulink.com/?emailconfirmed"
        else error "Confirmation code does not match logged in user."

sendPasswordReset :: App CGIResult
sendPasswordReset = do
  email <- getRequiredInput "email"
  -- The member's email address is either in the member table (for confirmed
  -- email addresses), or in the member_confirmation table. We keep them
  -- distinct in order to avoid sending email to unconfirmed addresses. In this
  -- case, however, we'll make an exception. It's likely that a user has
  -- forgotten their password shortly after signing up (before confirming their
  -- email address).
  memberNo <- $(queryTuple' "SELECT member_no FROM member WHERE email = {email} \
                            \UNION \
                            \SELECT member_no FROM member_confirmation WHERE email = {email} \
                            \LIMIT 1")
  case memberNo of
    Just (Just mn) -> do
      $(execute' "DELETE FROM password_reset_token WHERE member_no = {mn}")
      hash <- fromJust <$> $(queryTuple'
        "INSERT INTO password_reset_token (member_no, hash, expires) \
                                  \VALUES ({mn}, md5(random()::text), current_timestamp + interval '4 hours') \
        \RETURNING hash")
      let body = unlines [ "Password Reset"
                         , ""
                         , "Click http://www.vocabulink.com/member/password/reset/" ++
                           hash ++ " to reset your password."
                         , ""
                         , "The password reset page will only be available for 4 hours."
                         ]
      res <- liftIO $ sendMail email "Vocabulink Password Reset" body
      case res of
        Nothing -> error "Failed to send password reset email."
        _       -> outputNothing
    _              -> error "No member exists with that email address. Please try again."

passwordResetPage :: String -> App CGIResult
passwordResetPage hash = do
  memberNo <- $(queryTuple' "SELECT member_no FROM password_reset_token \
                            \WHERE hash = {hash} AND expires > current_timestamp")
  case memberNo of
    Just _  -> simplePage "Change Your Password" [] $ do
                 form ! action (stringValue $ "/member/password/reset/" ++ hash)
                      ! method "post"
                      ! style "width: 33em; margin-left: auto; margin-right: auto; text-align: center" $ do
                   label "Choose a new password: "
                   input ! type_ "password" ! name "password" ! customAttribute "required" "required"
                   br
                   br
                   input ! class_ "light" ! type_ "submit" ! value "Change Password"
    _             -> error "Invalid or expired password reset."

passwordReset :: String -> App CGIResult
passwordReset hash = do
  password <- getRequiredInput "password"
  memberNo <- $(queryTuple' "SELECT member_no FROM password_reset_token \
                            \WHERE hash = {hash} AND expires > current_timestamp")
  case memberNo of
    Just mn -> do
      $(execute' "UPDATE member SET password_hash = crypt({password}, password_hash) \
                 \WHERE member_no = {mn}")
      -- As a convenience, log the user in before redirecting them.
      ip      <- remoteAddr
      member' <- memberByNumber mn
      case member' of
        Nothing     -> error "Failed to lookup member."
        Just member -> do
          key <- fromJust <$> getOption "authtokenkey"
          authTok <- liftIO $ authToken (memberNumber member) (memberName member) ip key
          setAuthCookie authTok
          redirect "http://www.vocabulink.com/"
    _       -> error "Invalid or expired password reset."
