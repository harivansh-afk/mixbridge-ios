# Authenticated extraction rollout

Deploy mixbridge.app's Spotify exchange and stream-token routes first. Release this iOS client before enforcing bearer authentication on Spark's extraction API; older clients cannot supply these tokens. Existing Spotify logins must sign in again because their stored spotify:userId marker is not a signed session. Existing unexpired SoundCloud JWT sessions continue to work.

The app exchanges its Keychain session for a short-lived stream token for every extraction request. Stream tokens stay in memory and are never saved or reused across accounts. Session expiry is read from JWT exp for local UI only; authorization and signature verification remain server responsibilities.
