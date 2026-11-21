// Starts the Worker locally with `wrangler dev` (fresh state, no STUN) and returns {url, stop}.
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function startDevServer() {
  const port = 8790 + Math.floor(Math.random() * 100);
  const server = spawn(
    "npx",
    ["wrangler", "dev", "--port", String(port), "--ip", "127.0.0.1", "--var", "STUN_URLS:",
      "--persist-to", mkdtempSync(join(tmpdir(), "rendezvous-")), "--log-level", process.env.VERBOSE ? "log" : "warn"],
    {
      cwd: join(dirname(fileURLToPath(import.meta.url)), ".."),
      env: { ...process.env, WRANGLER_SEND_METRICS: "false", NO_PROXY: "127.0.0.1,localhost" },
      stdio: ["ignore", "pipe", "pipe"],
      shell: process.platform === "win32",
    },
  );
  server.stdout.on("data", (d) => process.env.VERBOSE && process.stdout.write(d));
  server.stderr.on("data", (d) => process.env.VERBOSE && process.stderr.write(d));
  const url = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 120; i++) {
    try {
      if ((await fetch(`${url}/health`)).ok) return { url, stop: () => server.kill() };
    } catch {}
    await sleep(500);
  }
  server.kill();
  throw new Error("wrangler dev didn't start");
}
