// MySQL connection layer, used alongside (not instead of) the in-memory
// store in lib/store.js. Records the pairing/connection status between a TV
// and an admin in a real table so it survives restarts and can be queried
// outside the app.
//
// Reads process.env.DATABASE_URL (see next/.env). If the DB is unreachable,
// callers degrade gracefully: the in-memory store keeps the app working,
// and a warning is logged instead of throwing.

import mysql from "mysql2/promise";
import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from "crypto";
import { promisify } from "util";

const scrypt = promisify(scryptCallback);

const DATABASE_URL =
  process.env.DATABASE_URL || "mysql://adwall_user:root@localhost:3306/adwall";

// Shared across HMR-reloaded route bundles in dev, same pattern as store.js.
const pool =
  globalThis.__adwallMysqlPool ??
  (globalThis.__adwallMysqlPool = mysql.createPool(DATABASE_URL));

const CREATE_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS tv_connections (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(6) NOT NULL UNIQUE,
    nickname VARCHAR(255) NOT NULL,
    tv_device_id VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'pending', /* 'pending' | 'paired' */
    playlist TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paired_at DATETIME NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );
`;

// Admin accounts, created by the master admin (see /api/admins). Passwords
// are never stored in plain text - see hashPassword/verifyPassword below.
// must_change_password starts true so a freshly created admin is prompted
// to pick their own password the first time they log in.
const CREATE_ADMINS_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS admins (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    must_change_password TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );
`;

// The single master-admin account for the /next dashboard (page.js). This is
// deliberately a different table from `admins`: the master admin creates and
// oversees regular admins, so it can't be just another row in that table.
// `singleton_guard` is always 1 and UNIQUE, so the database itself refuses a
// second row - this is what actually enforces "only 1 admin at a time" even
// under concurrent signup requests, not just a check in JS.
const CREATE_MASTER_ADMIN_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS master_admin (
    id INT AUTO_INCREMENT PRIMARY KEY,
    singleton_guard TINYINT NOT NULL UNIQUE DEFAULT 1,
    username VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  );
`;

// Login sessions for the master admin, persisted (not just in-memory) so a
// session survives a server restart or a shared-hosting process recycle.
// Tokens are opaque random strings; expired rows are simply ignored by
// verifyMasterAdminSession rather than actively swept.
const CREATE_MASTER_ADMIN_SESSIONS_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS master_admin_sessions (
    token VARCHAR(64) PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL
  );
`;

let schemaReadyPromise = null;

// Runs once per server process; idempotent (CREATE TABLE IF NOT EXISTS).
// Also adds the playlist column to tables created before it existed.
function ensureSchema() {
  if (!schemaReadyPromise) {
    schemaReadyPromise = pool
      .query(CREATE_TABLE_SQL)
      .then(() =>
        pool
          .query("ALTER TABLE tv_connections ADD COLUMN playlist TEXT NULL")
          .catch(() => {})
      )
      .then(() =>
        pool
          .query(
            "ALTER TABLE tv_connections ADD COLUMN admin_username VARCHAR(255) NULL"
          )
          .catch(() => {})
      )
      .then(() =>
        pool
          .query(
            "ALTER TABLE tv_connections ADD COLUMN orientation VARCHAR(20) NOT NULL DEFAULT 'landscape'"
          )
          .catch(() => {})
      )
      .then(() => pool.query(CREATE_ADMINS_TABLE_SQL))
      .then(() => pool.query(CREATE_MASTER_ADMIN_TABLE_SQL))
      .then(() => pool.query(CREATE_MASTER_ADMIN_SESSIONS_TABLE_SQL))
      .catch((err) => {
        console.warn("[db] failed to ensure tv_connections table exists:", err.message);
        schemaReadyPromise = null; // allow retry on next call
        throw err;
      });
  }
  return schemaReadyPromise;
}

// --- Password hashing ---------------------------------------------------
//
// scrypt (Node's built-in, no extra dependency) with a random per-password
// salt, stored together as "salt:hash" (both hex). Verification re-derives
// the hash with the stored salt and does a constant-time comparison.

async function hashPassword(password) {
  const salt = randomBytes(16).toString("hex");
  const derived = await scrypt(password, salt, 64);
  return `${salt}:${derived.toString("hex")}`;
}

async function verifyPassword(password, stored) {
  const [salt, hashHex] = (stored || "").split(":");
  if (!salt || !hashHex) return false;
  const expected = Buffer.from(hashHex, "hex");
  const derived = await scrypt(password, salt, expected.length);
  if (derived.length !== expected.length) return false;
  return timingSafeEqual(derived, expected);
}

/// Insert a new 'pending' row when the admin creates a code.
export async function recordCodeCreated(code, nickname, adminUsername) {
  try {
    await ensureSchema();
    await pool.query(
      `INSERT INTO tv_connections (code, nickname, status, admin_username)
       VALUES (?, ?, 'pending', ?)
       ON DUPLICATE KEY UPDATE
         nickname = VALUES(nickname),
         status = 'pending',
         tv_device_id = NULL,
         paired_at = NULL,
         admin_username = VALUES(admin_username)`,
      [code, nickname, adminUsername || null]
    );
  } catch (err) {
    console.warn("[db] recordCodeCreated failed:", err.message);
  }
}

/// Mark the row 'paired' once a TV claims the code.
export async function recordCodeClaimed(code, tvDeviceId) {
  try {
    await ensureSchema();
    await pool.query(
      `UPDATE tv_connections
         SET status = 'paired',
             tv_device_id = ?,
             paired_at = CURRENT_TIMESTAMP
       WHERE code = ?`,
      [tvDeviceId, code]
    );
  } catch (err) {
    console.warn("[db] recordCodeClaimed failed:", err.message);
  }
}

export async function recordPlaylistUpdated(code, playlist) {
  try {
    await ensureSchema();
    await pool.query(
      `UPDATE tv_connections SET playlist = ? WHERE code = ?`,
      [JSON.stringify(playlist), code]
    );
  } catch (err) {
    console.warn("[db] recordPlaylistUpdated failed:", err.message);
  }
}

export async function recordOrientationUpdated(code, orientation) {
  try {
    await ensureSchema();
    await pool.query(
      `UPDATE tv_connections SET orientation = ? WHERE code = ?`,
      [orientation, code]
    );
  } catch (err) {
    console.warn("[db] recordOrientationUpdated failed:", err.message);
  }
}

export async function loadAllPairings() {
  try {
    await ensureSchema();
    const [rows] = await pool.query(
      `SELECT code, nickname, tv_device_id, status, playlist, admin_username, orientation FROM tv_connections`
    );
    return rows.map((row) => ({
      code: row.code,
      nickname: row.nickname,
      tvDeviceId: row.tv_device_id,
      status: row.status,
      playlist: row.playlist ? JSON.parse(row.playlist) : [],
      adminUsername: row.admin_username,
      orientation: row.orientation || "landscape",
    }));
  } catch (err) {
    console.warn("[db] loadAllPairings failed:", err.message);
    return [];
  }
}

/// Permanently remove a TV's row (used when the admin deletes a TV).
export async function deleteTvConnection(code) {
  try {
    await ensureSchema();
    await pool.query(`DELETE FROM tv_connections WHERE code = ?`, [code]);
  } catch (err) {
    console.warn("[db] deleteTvConnection failed:", err.message);
  }
}

/// Permanently removes every TV row with no admin assigned. A TV can't
/// exist unassigned, so this is used both for one-off cleanup and could be
/// called after any operation that might otherwise leave one behind.
/// Returns the number of rows deleted.
export async function deleteUnassignedTvConnections() {
  await ensureSchema();
  const [result] = await pool.query(
    `DELETE FROM tv_connections WHERE admin_username IS NULL`
  );
  return result.affectedRows || 0;
}

// --- Admin accounts -------------------------------------------------------
//
// Unlike the TV-connection functions above, these throw on failure instead
// of swallowing errors: a DB hiccup here must not silently let a login
// succeed/fail incorrectly or let a duplicate username through.

/// Creates a new admin account with a hashed password. Throws with
/// code 'DUPLICATE_USERNAME' if the username is already taken.
export async function createAdmin(username, password) {
  await ensureSchema();
  const passwordHash = await hashPassword(password);
  try {
    await pool.query(
      `INSERT INTO admins (username, password_hash, must_change_password)
       VALUES (?, ?, 1)`,
      [username, passwordHash]
    );
  } catch (err) {
    if (err.code === "ER_DUP_ENTRY") {
      const dupErr = new Error("Username already exists");
      dupErr.code = "DUPLICATE_USERNAME";
      throw dupErr;
    }
    throw err;
  }
}

/// Verifies a username/password pair. Returns
/// { username, mustChangePassword } on success, or null if the username
/// doesn't exist or the password is wrong.
export async function verifyAdminLogin(username, password) {
  await ensureSchema();
  const [rows] = await pool.query(
    `SELECT username, password_hash, must_change_password FROM admins WHERE username = ?`,
    [username]
  );
  const row = rows[0];
  if (!row) return null;
  const ok = await verifyPassword(password, row.password_hash);
  if (!ok) return null;
  return {
    username: row.username,
    mustChangePassword: !!row.must_change_password,
  };
}

/// Updates an admin's password (after verifying their current one) and
/// clears the must_change_password flag. Returns false if the current
/// password doesn't match or the username doesn't exist.
export async function changeAdminPassword(username, currentPassword, newPassword) {
  await ensureSchema();
  const [rows] = await pool.query(
    `SELECT password_hash FROM admins WHERE username = ?`,
    [username]
  );
  const row = rows[0];
  if (!row) return false;
  const ok = await verifyPassword(currentPassword, row.password_hash);
  if (!ok) return false;
  const newHash = await hashPassword(newPassword);
  await pool.query(
    `UPDATE admins SET password_hash = ?, must_change_password = 0 WHERE username = ?`,
    [newHash, username]
  );
  return true;
}

/// Every admin username (for the master dashboard's admin list).
export async function listAdmins() {
  await ensureSchema();
  const [rows] = await pool.query(
    `SELECT username, must_change_password, created_at FROM admins ORDER BY created_at DESC`
  );
  return rows.map((row) => ({
    username: row.username,
    mustChangePassword: !!row.must_change_password,
    createdAt: row.created_at,
  }));
}

// --- Master admin (single account, dashboard login) -----------------------
//
// Throws on failure (same reasoning as the admins functions above): a DB
// hiccup here must not silently let a login/signup succeed or fail wrong.

const MASTER_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

/// Whether a master admin account has already been created. The dashboard
/// uses this to decide whether to show the signup button at all.
export async function masterAdminExists() {
  await ensureSchema();
  const [rows] = await pool.query(`SELECT id FROM master_admin LIMIT 1`);
  return rows.length > 0;
}

/// Creates the one and only master admin account. Throws with code
/// 'MASTER_ADMIN_EXISTS' if one already exists (also enforced at the DB
/// level by the singleton_guard UNIQUE column, so this is race-safe).
export async function createMasterAdmin(username, password) {
  await ensureSchema();
  const passwordHash = await hashPassword(password);
  try {
    await pool.query(
      `INSERT INTO master_admin (username, password_hash) VALUES (?, ?)`,
      [username, passwordHash]
    );
  } catch (err) {
    if (err.code === "ER_DUP_ENTRY") {
      const dupErr = new Error("A master admin account already exists.");
      dupErr.code = "MASTER_ADMIN_EXISTS";
      throw dupErr;
    }
    throw err;
  }
  return createMasterAdminSession(username);
}

/// Verifies the master admin's username/password. Returns a fresh session
/// token on success, or null if the credentials don't match.
export async function verifyMasterAdminLogin(username, password) {
  await ensureSchema();
  const [rows] = await pool.query(
    `SELECT username, password_hash FROM master_admin WHERE username = ?`,
    [username]
  );
  const row = rows[0];
  if (!row) return null;
  const ok = await verifyPassword(password, row.password_hash);
  if (!ok) return null;
  return createMasterAdminSession(row.username);
}

async function createMasterAdminSession(username) {
  const token = randomBytes(32).toString("hex");
  const expiresAt = new Date(Date.now() + MASTER_SESSION_TTL_MS);
  await pool.query(
    `INSERT INTO master_admin_sessions (token, username, expires_at) VALUES (?, ?, ?)`,
    [token, username, expiresAt]
  );
  return { username, token };
}

/// Verifies a bearer token from the Authorization header. Returns the
/// master admin's username if the token is valid and unexpired, else null.
export async function verifyMasterAdminSession(token) {
  if (!token) return null;
  await ensureSchema();
  const [rows] = await pool.query(
    `SELECT username, expires_at FROM master_admin_sessions WHERE token = ?`,
    [token]
  );
  const row = rows[0];
  if (!row) return null;
  if (new Date(row.expires_at).getTime() < Date.now()) return null;
  return row.username;
}

/// Logs the master admin out by deleting their session token.
export async function deleteMasterAdminSession(token) {
  if (!token) return;
  await ensureSchema();
  await pool.query(`DELETE FROM master_admin_sessions WHERE token = ?`, [token]);
}

export { pool };


