// MySQL connection layer, used alongside (not instead of) the in-memory
// store in lib/store.js. Records the pairing/connection status between a TV
// and an admin in a real table so it survives restarts and can be queried
// outside the app.
//
// Reads process.env.DATABASE_URL (see next/.env). If the DB is unreachable,
// callers degrade gracefully: the in-memory store keeps the app working,
// and a warning is logged instead of throwing.

import mysql from "mysql2/promise";

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
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paired_at DATETIME NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );
`;

let schemaReadyPromise = null;

// Runs once per server process; idempotent (CREATE TABLE IF NOT EXISTS).
function ensureSchema() {
  if (!schemaReadyPromise) {
    schemaReadyPromise = pool.query(CREATE_TABLE_SQL).catch((err) => {
      console.warn("[db] failed to ensure tv_connections table exists:", err.message);
      schemaReadyPromise = null; // allow retry on next call
      throw err;
    });
  }
  return schemaReadyPromise;
}

/// Insert a new 'pending' row when the admin creates a code.
export async function recordCodeCreated(code, nickname) {
  try {
    await ensureSchema();
    await pool.query(
      `INSERT INTO tv_connections (code, nickname, status)
       VALUES (?, ?, 'pending')
       ON DUPLICATE KEY UPDATE
         nickname = VALUES(nickname),
         status = 'pending',
         tv_device_id = NULL,
         paired_at = NULL`,
      [code, nickname]
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

export { pool };
