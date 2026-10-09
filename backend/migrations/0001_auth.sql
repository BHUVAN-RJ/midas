-- Auth for build 1: a display name plus a passkey. Nothing else identifies a user.
-- Apply with: npx wrangler d1 migrations apply midas --remote

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- One row per passkey. public_key is the COSE key, base64url encoded.
CREATE TABLE passkeys (
  credential_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  public_key TEXT NOT NULL,
  counter INTEGER NOT NULL,
  transports TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX passkeys_by_user ON passkeys(user_id);

-- Single use: a challenge row is deleted when it is verified. user_id and user_name are set
-- only for registration, where the user row does not exist until the passkey is verified.
CREATE TABLE auth_challenges (
  id TEXT PRIMARY KEY,
  challenge TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('register', 'login')),
  user_id TEXT,
  user_name TEXT,
  expires_at INTEGER NOT NULL
);

-- Only the SHA-256 of a session token is stored; the token itself lives in the phone's Keychain.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX sessions_by_user ON sessions(user_id);
