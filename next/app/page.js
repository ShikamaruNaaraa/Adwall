"use client";

import { useEffect, useState, useCallback } from "react";

const PASSWORD_HINT =
  "At least 8 characters, with at least 1 letter and 1 number.";

function isValidPassword(password) {
  return (
    password.length >= 8 && /[A-Za-z]/.test(password) && /[0-9]/.test(password)
  );
}

function TvCard({ tv }) {
  return (
    <div
      style={{
        border: "1px solid #e2e2e2",
        borderRadius: 8,
        padding: 12,
        marginTop: 8,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <strong>{tv.nickname}</strong>
        <span
          style={{
            fontSize: 12,
            padding: "2px 8px",
            borderRadius: 999,
            background: tv.connected ? "#e6f4ea" : "#fdecea",
            color: tv.connected ? "#1e8449" : "#c0392b",
          }}
        >
          {tv.status === "paired" ? (tv.connected ? "Connected" : "Disconnected") : "Pending"}
        </span>
      </div>
      <div style={{ fontSize: 13, color: "#777", marginTop: 2 }}>Code: {tv.code}</div>
      {tv.playlist.length === 0 ? (
        <div style={{ fontSize: 13, color: "#999", marginTop: 6 }}>No ads set.</div>
      ) : (
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            gap: 10,
            marginTop: 8,
          }}
        >
          {tv.playlist.map((item, i) => (
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
                  border: "1px solid #e2e2e2",
                  borderRadius: 6,
                  overflow: "hidden",
                  background: "#f5f5f5",
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
                <div style={{ fontSize: 11, color: "#666", padding: "3px 4px" }}>
                  {item.mediaType} · {item.durationSeconds}s
                </div>
              </div>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}

function AdminCard({ admin }) {
  return (
    <div
      style={{
        border: "1px solid #ddd",
        borderRadius: 10,
        padding: 16,
        marginTop: 16,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h3 style={{ margin: 0, fontSize: 16 }}>{admin.username}</h3>
        {admin.mustChangePassword && (
          <span style={{ fontSize: 12, color: "#b7791f" }}>Password not yet changed</span>
        )}
      </div>
      {admin.tvs.length === 0 ? (
        <p style={{ fontSize: 13, color: "#999", marginTop: 8 }}>No TVs added yet.</p>
      ) : (
        admin.tvs.map((tv) => <TvCard key={tv.code} tv={tv} />)
      )}
    </div>
  );
}

export default function Home() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);
  const [created, setCreated] = useState(null);

  const [overview, setOverview] = useState(null);
  const [overviewError, setOverviewError] = useState(null);

  const loadOverview = useCallback(async () => {
    try {
      const res = await fetch("/api/admins-overview");
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(body.detail || "Failed to load admins overview.");
      }
      setOverview(body);
      setOverviewError(null);
    } catch (err) {
      setOverviewError(err.message);
    }
  }, []);

  useEffect(() => {
    loadOverview();
  }, [loadOverview]);

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
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: trimmedUsername, password }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(body.detail || "Failed to create admin.");
      }
      setCreated(trimmedUsername);
      setUsername("");
      setPassword("");
      loadOverview();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main
      style={{
        fontFamily: "system-ui, Arial, sans-serif",
        maxWidth: 720,
        margin: "0 auto",
        padding: "48px 24px",
      }}
    >
      <h1 style={{ fontSize: 24, marginBottom: 4 }}>AdWall Master Admin</h1>
      <p style={{ color: "#555", marginTop: 0 }}>
        Create admin accounts. Give the username and password to the admin -
        they&apos;ll be asked to set their own password the first time they
        log in.
      </p>

      <form
        onSubmit={handleSubmit}
        style={{ display: "flex", flexDirection: "column", gap: 12, marginTop: 24, maxWidth: 480 }}
      >
        <label style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          Username
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoComplete="off"
            style={{ padding: 10, fontSize: 16, border: "1px solid #ccc", borderRadius: 6 }}
          />
        </label>

        <label style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          Password
          <input
            type="text"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="off"
            style={{ padding: 10, fontSize: 16, border: "1px solid #ccc", borderRadius: 6 }}
          />
          <span style={{ fontSize: 13, color: "#777" }}>{PASSWORD_HINT}</span>
        </label>

        {error && <p style={{ color: "#c0392b", margin: 0 }}>{error}</p>}
        {created && (
          <p style={{ color: "#1e8449", margin: 0 }}>
            Admin &quot;{created}&quot; created.
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          style={{
            padding: "10px 16px",
            fontSize: 16,
            borderRadius: 6,
            border: "none",
            background: submitting ? "#999" : "#2f4b7c",
            color: "white",
            cursor: submitting ? "default" : "pointer",
          }}
        >
          {submitting ? "Adding..." : "Add admin user"}
        </button>
      </form>

      <section style={{ marginTop: 48 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <h2 style={{ fontSize: 18, margin: 0 }}>Admins, TVs &amp; ads</h2>
          <button
            onClick={loadOverview}
            style={{
              fontSize: 13,
              padding: "6px 10px",
              borderRadius: 6,
              border: "1px solid #ccc",
              background: "white",
              cursor: "pointer",
            }}
          >
            Refresh
          </button>
        </div>

        {overviewError && <p style={{ color: "#c0392b" }}>{overviewError}</p>}

        {!overview && !overviewError && <p style={{ color: "#777" }}>Loading...</p>}

        {overview && overview.admins.length === 0 && (
          <p style={{ color: "#777" }}>No admins yet.</p>
        )}

        {overview &&
          overview.admins.map((admin) => (
            <AdminCard key={admin.username} admin={admin} />
          ))}

        {overview && overview.unassignedTvs.length > 0 && (
          <div style={{ marginTop: 16 }}>
            <h3 style={{ fontSize: 15, color: "#777" }}>Unassigned TVs</h3>
            {overview.unassignedTvs.map((tv) => (
              <TvCard key={tv.code} tv={tv} />
            ))}
          </div>
        )}
      </section>
    </main>
  );
}