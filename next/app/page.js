"use client";

import { useEffect, useState } from "react";

export default function Home() {
  const [uptime, setUptime] = useState(0);

  useEffect(() => {
    const started = Date.now();

    const timer = setInterval(() => {
      setUptime(Math.floor((Date.now() - started) / 1000));
    }, 1000);

    return () => clearInterval(timer);
  }, []);

  const days = Math.floor(uptime / 86400);
  const hours = Math.floor((uptime % 86400) / 3600);
  const minutes = Math.floor((uptime % 3600) / 60);
  const seconds = uptime % 60;

  return (
    <main
      style={{
        fontFamily: "Arial",
        textAlign: "center",
        paddingTop: "100px"
      }}
    >
      <h1>Next.js Process Test</h1>

      <h2 style={{ color: "green" }}>
        ● APPLICATION RUNNING
      </h2>

      <h1>Page Uptime</h1>

      <div style={{ fontSize: "48px", fontWeight: "bold" }}>
        {String(days).padStart(2, "0")}:
        {String(hours).padStart(2, "0")}:
        {String(minutes).padStart(2, "0")}:
        {String(seconds).padStart(2, "0")}
      </div>

      <p>
        This page is running through Next.js on Hostinger.
      </p>
    </main>
  );
}