"use client";

import { useEffect, useState, useCallback } from "react";

const PASSWORD_HINT =
  "At least 8 characters, with at least 1 letter and 1 number.";

const TOKEN_KEY = "adwall_master_admin_token";
const USERNAME_KEY = "adwall_master_admin_username";

// --- Theme -----------------------------------------------------------------
// Light green + light blue + white, used consistently across the login
// screen and the dashboard. A single object so every component pulls from
// the same palette instead of scattering hex values.
const theme = {
  white: "#ffffff",
  green: "#2fa876", // primary accent - buttons, active nav state
  greenSoft: "#e6f6ef", // pale green surface (sidebar wash, hovered rows)
  greenBorder: "#bfe8d5",
  blue: "#3b82c4", // secondary accent - links, info states
  blueSoft: "#eaf4fc", // pale blue surface (page background)
  blueBorder: "#c6e2f5",
  text: "#1f2a37",
  textMuted: "#64748b",
  danger: "#c0392b",
  dangerSoft: "#fdecea",
};

const fontFamily =
  "'Segoe UI', system-ui, -apple-system, Arial, sans-serif";

function isValidPassword(password) {
  return (
    password.length >= 8 && /[A-Za-z]/.test(password) && /[0-9]/.test(password)
  );
}

function Card({ children, style }) {
  return (
    <div
      style={{
        background: theme.white,
        border: `1px solid ${theme.blueBorder}`,
        borderRadius: 12,
        boxShadow: "0 1px 3px rgba(31, 42, 55, 0.06)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function PrimaryButton({ children, disabled, ...props }) {
  return (
    <button
      disabled={disabled}
      {...props}
      style={{
        padding: "10px 18px",
        fontSize: 15,
        fontWeight: 600,
        borderRadius: 8,
        border: "none",
        background: disabled ? "#9fd6bd" : theme.green,
        color: theme.white,
        cursor: disabled ? "default" : "pointer",
        transition: "background 0.15s ease",
      }}
    >
      {children}
    </button>
  );
}

function SecondaryButton({ children, ...props }) {
  return (
    <button
      {...props}
      style={{
        fontSize: 13,
        fontWeight: 600,
        padding: "8px 14px",
        borderRadius: 8,
        border: `1px solid ${theme.blueBorder}`,
        background: theme.white,
        color: theme.blue,
        cursor: "pointer",
      }}
    >
      {children}
    </button>
  );
}

function Chevron({ open }) {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      style={{
        transform: open ? "rotate(180deg)" : "rotate(0deg)",
        transition: "transform 0.15s ease",
        flexShrink: 0,
      }}
    >
      <path
        d="M6 9l6 6 6-6"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function AdList({ playlist }) {
  if (playlist.length === 0) {
    return <div style={{ fontSize: 13, color: theme.textMuted, marginTop: 6 }}>No ads set.</div>;
  }
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 10, marginTop: 10 }}>
      {playlist.map((item, i) => (
        <a
          key={i}
          href={item.mediaUrl}
          target="_blank"
          rel="noopener noreferrer"
          style={{ textDecoration: "none", color: "inherit" }}
        >
          <div
            style={{
              width: 96,
              border: `1px solid ${theme.blueBorder}`,
              borderRadius: 8,
              overflow: "hidden",
              background: theme.blueSoft,
            }}
          >
            {item.mediaType === "video" ? (
              <video
                src={item.mediaUrl}
                muted
                style={{ width: "100%", height: 64, objectFit: "cover", display: "block" }}
              />
            ) : (
              <img
                src={item.mediaUrl}
                alt="ad"
                style={{ width: "100%", height: 64, objectFit: "cover", display: "block" }}
              />
            )}
            <div style={{ fontSize: 11, color: theme.textMuted, padding: "3px 4px" }}>
              {item.mediaType} · {item.durationSeconds}s
            </div>
          </div>
        </a>
      ))}
    </div>
  );
}

// A single TV row inside an admin's dropdown. Click the row to sweep open a
// panel of the ads currently on that TV's playlist.
function TvRow({ tv, expanded, onToggle }) {
  return (
    <div
      style={{
        border: `1px solid ${theme.blueBorder}`,
        borderRadius: 10,
        marginTop: 8,
        background: theme.white,
        overflow: "hidden",
      }}
    >
      <button
        onClick={onToggle}
        style={{
          display: "flex",
          width: "100%",
          justifyContent: "space-between",
          alignItems: "center",
          gap: 10,
          padding: 12,
          border: "none",
          background: "transparent",
          cursor: "pointer",
          textAlign: "left",
          color: theme.text,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
          <Chevron open={expanded} />
          <div style={{ minWidth: 0 }}>
            <strong style={{ color: theme.text }}>{tv.nickname}</strong>
            <div style={{ fontSize: 12, color: theme.textMuted }}>Code: {tv.code}</div>
          </div>
        </div>
        <span
          style={{
            fontSize: 12,
            fontWeight: 600,
            padding: "2px 10px",
            borderRadius: 999,
            background: tv.connected ? theme.greenSoft : theme.dangerSoft,
            color: tv.connected ? theme.green : theme.danger,
            flexShrink: 0,
          }}
        >
          {tv.status === "paired" ? (tv.connected ? "Connected" : "Disconnected") : "Pending"}
        </span>
      </button>

      {expanded && (
        <div style={{ padding: "0 12px 12px" }}>
          <div style={{ fontSize: 12, fontWeight: 600, color: theme.textMuted, marginTop: 2 }}>
            Ads on this TV
          </div>
          <AdList playlist={tv.playlist} />
        </div>
      )}
    </div>
  );
}

// One admin's row in the accordion. Click the admin to sweep down their list
// of TVs; click a TV to sweep down its ads.
function AdminRow({ admin, expanded, onToggle, expandedTv, onToggleTv }) {
  return (
    <Card style={{ marginTop: 12, overflow: "hidden" }}>
      <button
        onClick={onToggle}
        style={{
          display: "flex",
          width: "100%",
          justifyContent: "space-between",
          alignItems: "center",
          gap: 10,
          padding: 16,
          border: "none",
          background: "transparent",
          cursor: "pointer",
          textAlign: "left",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <Chevron open={expanded} />
          <h3 style={{ margin: 0, fontSize: 16, color: theme.text }}>{admin.username}</h3>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          {admin.mustChangePassword && (
            <span style={{ fontSize: 12, color: "#b7791f" }}>Password not yet changed</span>
          )}
          <span style={{ fontSize: 12, color: theme.textMuted }}>
            {admin.tvs.length} TV{admin.tvs.length === 1 ? "" : "s"}
          </span>
        </div>
      </button>

      {expanded && (
        <div style={{ padding: "0 16px 16px" }}>
          {admin.tvs.length === 0 ? (
            <p style={{ fontSize: 13, color: theme.textMuted, margin: 0 }}>No TVs added yet.</p>
          ) : (
            admin.tvs.map((tv) => (
              <TvRow
                key={tv.code}
                tv={tv}
                expanded={expandedTv === tv.code}
                onToggle={() => onToggleTv(tv.code)}
              />
            ))
          )}
        </div>
      )}
    </Card>
  );
}


// Login (and, only before the one master admin account exists, signup) form
// for the dashboard. Once an account has been created, /api/master-admin
// reports exists: true and the signup button disappears for good, and there
// is deliberately no way to delete or replace that account from the app -
// only login remains, matching "only 1 admin, ever".
function AuthGate({ onAuthenticated }) {
  const [checking, setChecking] = useState(true);
  const [masterExists, setMasterExists] = useState(null);
  const [mode, setMode] = useState("login"); // 'login' | 'signup'
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch("/api/master-admin")
      .then((res) => res.json())
      .then((body) => {
        setMasterExists(!!body.exists);
        setMode(body.exists ? "login" : "signup");
      })
      .catch(() => setMasterExists(true)) // fail safe: assume it exists, only offer login
      .finally(() => setChecking(false));
  }, []);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);

    const trimmedUsername = username.trim();
    if (!trimmedUsername || !password) {
      setError("Username and password are required.");
      return;
    }
    if (mode === "signup" && !isValidPassword(password)) {
      setError(PASSWORD_HINT);
      return;
    }

    setSubmitting(true);
    try {
      const endpoint = mode === "signup" ? "/api/master-admin/signup" : "/api/master-admin/login";
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: trimmedUsername, password }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        // If signup just lost a race (someone else just created the account),
        // fall back to the login form instead of dead-ending.
        if (res.status === 409) {
          setMasterExists(true);
          setMode("login");
        }
        throw new Error(body.detail || "Something went wrong.");
      }
      localStorage.setItem(TOKEN_KEY, body.token);
      localStorage.setItem(USERNAME_KEY, body.username);
      onAuthenticated(body.username, body.token);
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }

  const wrapStyle = {
    fontFamily,
    minHeight: "100vh",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    background: `linear-gradient(135deg, ${theme.blueSoft} 0%, ${theme.white} 55%, ${theme.greenSoft} 100%)`,
  };

  if (checking) {
    return (
      <main style={wrapStyle}>
        <p style={{ color: theme.textMuted }}>Loading...</p>
      </main>
    );
  }

  return (
    <main style={wrapStyle}>
      <Card style={{ width: "100%", maxWidth: 400, padding: "36px 32px", margin: "0 24px" }}>
        <h1 style={{ fontSize: 22, marginBottom: 4, color: theme.text }}>AdWall</h1>
        <p style={{ color: theme.textMuted, marginTop: 0, fontSize: 14 }}>
          {mode === "signup"
            ? "Create the master admin account. This can only be done once."
            : "Log in to manage admin accounts, TVs and ads."}
        </p>

        <form
          onSubmit={handleSubmit}
          style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 20 }}
        >
          <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13, color: theme.text }}>
            Username
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              style={{ padding: 10, fontSize: 15, border: `1px solid ${theme.blueBorder}`, borderRadius: 8 }}
            />
          </label>

          <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13, color: theme.text }}>
            Password
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete={mode === "signup" ? "new-password" : "current-password"}
              style={{ padding: 10, fontSize: 15, border: `1px solid ${theme.blueBorder}`, borderRadius: 8 }}
            />
            {mode === "signup" && (
              <span style={{ fontSize: 12, color: theme.textMuted }}>{PASSWORD_HINT}</span>
            )}
          </label>

          {error && <p style={{ color: theme.danger, margin: 0, fontSize: 13 }}>{error}</p>}

          <PrimaryButton type="submit" disabled={submitting}>
            {submitting ? "Please wait..." : mode === "signup" ? "Create master admin" : "Log in"}
          </PrimaryButton>
        </form>

        {/* The signup button only ever appears when no master admin exists yet
            (masterExists === false). Once one has been created it is gone for
            good - only the toggle back to login (if the user landed on signup
            from a stale page) remains available, and that toggle is hidden too
            once masterExists is true. */}
        {masterExists === false && (
          <p style={{ marginTop: 16, fontSize: 13, color: theme.textMuted }}>
            {mode === "signup" ? (
              <>
                Already created an account?{" "}
                <button
                  type="button"
                  onClick={() => setMode("login")}
                  style={{ border: "none", background: "none", color: theme.blue, cursor: "pointer", padding: 0, font: "inherit" }}
                >
                  Log in instead
                </button>
              </>
            ) : (
              <>
                No master admin yet?{" "}
                <button
                  type="button"
                  onClick={() => setMode("signup")}
                  style={{ border: "none", background: "none", color: theme.blue, cursor: "pointer", padding: 0, font: "inherit" }}
                >
                  Sign up
                </button>
              </>
            )}
          </p>
        )}
      </Card>
    </main>
  );
}

function NavItem({ label, active, onClick }) {
  return (
    <button
      onClick={onClick}
      style={{
        display: "block",
        width: "100%",
        textAlign: "left",
        padding: "10px 16px",
        fontSize: 14,
        fontWeight: active ? 700 : 500,
        borderRadius: 8,
        border: "none",
        cursor: "pointer",
        background: active ? theme.greenSoft : "transparent",
        color: active ? theme.green : theme.text,
      }}
    >
      {label}
    </button>
  );
}

function CreateAdminPanel({ authHeaders, onLogout, onAdminCreated }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);
  const [created, setCreated] = useState(null);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setCreated(null);

    const trimmedUsername = username.trim();
    if (!trimmedUsername) {
      setError("Username is required.");
      return;
    }
    if (!isValidPassword(password)) {
      setError(PASSWORD_HINT);
      return;
    }

    setSubmitting(true);
    try {
      const res = await fetch("/api/admins", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...authHeaders() },
        body: JSON.stringify({ username: trimmedUsername, password }),
      });
      const body = await res.json().catch(() => ({}));
      if (res.status === 401) {
        onLogout();
        return;
      }
      if (!res.ok) {
        throw new Error(body.detail || "Failed to create admin.");
      }
      setCreated(trimmedUsername);
      setUsername("");
      setPassword("");
      onAdminCreated();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div>
      <h1 style={{ fontSize: 22, marginBottom: 4, color: theme.text }}>Create admin user</h1>
      <p style={{ color: theme.textMuted, marginTop: 0, fontSize: 14 }}>
        Give the username and password to the admin - they&apos;ll be asked to set their
        own password the first time they log in.
      </p>

      <Card style={{ padding: 24, marginTop: 20, maxWidth: 440 }}>
        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13, color: theme.text }}>
            Username
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="off"
              style={{ padding: 10, fontSize: 15, border: `1px solid ${theme.blueBorder}`, borderRadius: 8 }}
            />
          </label>

          <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13, color: theme.text }}>
            Password
            <input
              type="text"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="off"
              style={{ padding: 10, fontSize: 15, border: `1px solid ${theme.blueBorder}`, borderRadius: 8 }}
            />
            <span style={{ fontSize: 12, color: theme.textMuted }}>{PASSWORD_HINT}</span>
          </label>

          {error && <p style={{ color: theme.danger, margin: 0, fontSize: 13 }}>{error}</p>}
          {created && (
            <p style={{ color: theme.green, margin: 0, fontSize: 13, fontWeight: 600 }}>
              Admin &quot;{created}&quot; created.
            </p>
          )}

          <PrimaryButton type="submit" disabled={submitting} style={{ alignSelf: "flex-start" }}>
            {submitting ? "Adding..." : "Add admin user"}
          </PrimaryButton>
        </form>
      </Card>
    </div>
  );
}

function OverviewPanel({ authHeaders, onLogout, reloadToken }) {
  const [overview, setOverview] = useState(null);
  const [overviewError, setOverviewError] = useState(null);
  const [query, setQuery] = useState("");
  const [expandedAdmin, setExpandedAdmin] = useState(null);
  const [expandedTv, setExpandedTv] = useState(null);

  const loadOverview = useCallback(async () => {
    try {
      const res = await fetch("/api/admins-overview", { headers: authHeaders() });
      const body = await res.json().catch(() => ({}));
      if (res.status === 401) {
        onLogout();
        return;
      }
      if (!res.ok) {
        throw new Error(body.detail || "Failed to load admins overview.");
      }
      setOverview(body);
      setOverviewError(null);
    } catch (err) {
      setOverviewError(err.message);
    }
  }, [authHeaders, onLogout]);

  useEffect(() => {
    loadOverview();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loadOverview, reloadToken]);

  const trimmedQuery = query.trim().toLowerCase();
  const matchesQuery = useCallback(
    (admin) => {
      if (!trimmedQuery) return true;
      if (admin.username.toLowerCase().includes(trimmedQuery)) return true;
      return admin.tvs.some((tv) => tv.nickname.toLowerCase().includes(trimmedQuery));
    },
    [trimmedQuery]
  );

  const filteredAdmins = overview ? overview.admins.filter(matchesQuery) : [];
  const filteredUnassignedTvs = overview
    ? overview.unassignedTvs.filter(
        (tv) => !trimmedQuery || tv.nickname.toLowerCase().includes(trimmedQuery)
      )
    : [];

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <h1 style={{ fontSize: 22, marginBottom: 4, color: theme.text }}>Admins, TVs &amp; ads</h1>
          <p style={{ color: theme.textMuted, marginTop: 0, fontSize: 14 }}>
            Click an admin to see their TVs, then click a TV to see its ads.
          </p>
        </div>
        <SecondaryButton onClick={loadOverview}>Refresh</SecondaryButton>
      </div>

      <div style={{ marginTop: 16, maxWidth: 360 }}>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search by admin or TV name"
          style={{
            width: "100%",
            padding: "10px 12px",
            fontSize: 14,
            border: `1px solid ${theme.blueBorder}`,
            borderRadius: 8,
            background: theme.white,
            color: theme.text,
            boxSizing: "border-box",
          }}
        />
      </div>

      {overviewError && <p style={{ color: theme.danger, marginTop: 16 }}>{overviewError}</p>}

      {!overview && !overviewError && <p style={{ color: theme.textMuted, marginTop: 16 }}>Loading...</p>}

      {overview && overview.admins.length === 0 && (
        <p style={{ color: theme.textMuted, marginTop: 16 }}>No admins yet.</p>
      )}

      {overview && overview.admins.length > 0 && filteredAdmins.length === 0 && (
        <p style={{ color: theme.textMuted, marginTop: 16 }}>No admins or TVs match &quot;{query}&quot;.</p>
      )}

      {filteredAdmins.map((admin) => (
        <AdminRow
          key={admin.username}
          admin={admin}
          expanded={expandedAdmin === admin.username}
          onToggle={() =>
            setExpandedAdmin((current) => (current === admin.username ? null : admin.username))
          }
          expandedTv={expandedTv}
          onToggleTv={(code) => setExpandedTv((current) => (current === code ? null : code))}
        />
      ))}

      {overview && filteredUnassignedTvs.length > 0 && (
        <div style={{ marginTop: 20 }}>
          <h3 style={{ fontSize: 15, color: theme.textMuted, fontWeight: 600 }}>Unassigned TVs</h3>
          {filteredUnassignedTvs.map((tv) => (
            <TvRow
              key={tv.code}
              tv={tv}
              expanded={expandedTv === tv.code}
              onToggle={() => setExpandedTv((current) => (current === tv.code ? null : tv.code))}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function Dashboard({ masterUsername, token, onLogout }) {
  const [section, setSection] = useState("overview"); // 'create' | 'overview'
  const [reloadToken, setReloadToken] = useState(0);

  const authHeaders = useCallback(
    () => ({ Authorization: `Bearer ${token}` }),
    [token]
  );

  return (
    <div
      style={{
        fontFamily,
        minHeight: "100vh",
        display: "flex",
        background: theme.blueSoft,
      }}
    >
      {/* Left nav */}
      <aside
        style={{
          width: 232,
          flexShrink: 0,
          background: theme.white,
          borderRight: `1px solid ${theme.blueBorder}`,
          display: "flex",
          flexDirection: "column",
          padding: "20px 12px",
          position: "sticky",
          top: 0,
          height: "100vh",
        }}
      >
        <div style={{ padding: "4px 8px 20px" }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: theme.text }}>AdWall</div>
          <div style={{ fontSize: 11, color: theme.textMuted }}>Master Admin</div>
        </div>

        <nav style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <NavItem
            label="Create admin user"
            active={section === "create"}
            onClick={() => setSection("create")}
          />
          <NavItem
            label="Admins, TVs & ads"
            active={section === "overview"}
            onClick={() => setSection("overview")}
          />
        </nav>

        {/* Pinned to the bottom of the sidebar */}
        <div style={{ marginTop: "auto", paddingTop: 16, borderTop: `1px solid ${theme.blueBorder}` }}>
          <div style={{ padding: "0 8px 10px", fontSize: 12, color: theme.textMuted }}>
            Signed in as <strong style={{ color: theme.text }}>{masterUsername}</strong>
          </div>
          <button
            onClick={onLogout}
            style={{
              display: "block",
              width: "100%",
              textAlign: "left",
              padding: "10px 16px",
              fontSize: 14,
              fontWeight: 600,
              borderRadius: 8,
              border: "none",
              cursor: "pointer",
              background: "transparent",
              color: theme.danger,
            }}
          >
            Log out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main style={{ flex: 1, padding: "40px 40px", maxWidth: 880 }}>
        {section === "create" ? (
          <CreateAdminPanel
            authHeaders={authHeaders}
            onLogout={onLogout}
            onAdminCreated={() => setReloadToken((n) => n + 1)}
          />
        ) : (
          <OverviewPanel authHeaders={authHeaders} onLogout={onLogout} reloadToken={reloadToken} />
        )}
      </main>
    </div>
  );
}

export default function Home() {
  // null = still checking localStorage/session; false = need to show AuthGate.
  const [session, setSession] = useState(null);

  useEffect(() => {
    const token = localStorage.getItem(TOKEN_KEY);
    const username = localStorage.getItem(USERNAME_KEY);
    setSession(token && username ? { token, username } : false);
  }, []);

  const handleLogout = useCallback(() => {
    const token = localStorage.getItem(TOKEN_KEY);
    if (token) {
      fetch("/api/master-admin/logout", {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      }).catch(() => {});
    }
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USERNAME_KEY);
    setSession(false);
  }, []);

  if (session === null) {
    return (
      <main style={{ fontFamily, minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <p style={{ color: theme.textMuted }}>Loading...</p>
      </main>
    );
  }

  if (!session) {
    return (
      <AuthGate
        onAuthenticated={(username, token) => setSession({ username, token })}
      />
    );
  }

  return (
    <Dashboard masterUsername={session.username} token={session.token} onLogout={handleLogout} />
  );
}