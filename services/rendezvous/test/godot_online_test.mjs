// Starts the rendezvous service locally, then runs the Godot multiplayer test online: the host gets a join code,
// a second Godot joins with it, and they play over WebRTC.
//   cd services/rendezvous && node test/godot_online_test.mjs [path to godot]
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { startDevServer } from "./dev_server.mjs";

const godot = process.argv[2] || process.env.GODOT || "godot";
const project = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "shopping-cart");
const server = await startDevServer();
const run = spawnSync(godot, ["--headless", "--path", project, "-s", "res://tests/multiplayer_test.gd", "--", "--online", `--rendezvous=${server.url}`], {
  stdio: "inherit",
  env: { ...process.env, NO_PROXY: "127.0.0.1,localhost" },
});
server.stop();
process.exit(run.status ?? 1);
