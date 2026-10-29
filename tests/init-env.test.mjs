import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = mkdtempSync(join(tmpdir(), "pncp-worker-env-"));
try {
  mkdirSync(join(dir, ".secrets"), { mode: 0o700 });
  writeFileSync(join(dir, ".secrets/database.crt"), "fixture-only-ca", {
    mode: 0o600,
  });
  const init = fileURLToPath(new URL("../scripts/init.mjs", import.meta.url));
  const run = () =>
    spawnSync(process.execPath, [init], { cwd: dir, encoding: "utf8" });
  const first = run();
  assert.equal(first.status, 0, first.stderr);
  const worker = readFileSync(join(dir, ".env.worker"), "utf8");
  assert.doesNotMatch(worker, /WORKER_POLL_INTERVAL_MS/);
  assert.match(worker, /WORKER_COMPANY_IDS=''/);
  assert.match(worker, /OPENAI_API_KEY=''/);
  assert.match(worker, /RESEND_API_KEY=''/);
  assert.match(worker, /WORKER_MAX_EVALUATIONS_PER_RUN='4'/);
  for (const filename of [
    ".env.app",
    ".env.worker",
    ".env.database",
    ".env.migrate",
    ".env.backup",
  ]) {
    assert.equal(statSync(join(dir, filename)).mode & 0o777, 0o600);
  }
  const second = run();
  assert.notEqual(second.status, 0, "Bootstrap must not overwrite secrets");
  process.stdout.write(
    "PASS: isolated deploy bootstrap generates least-privilege worker env without unused polling and refuses overwrites.\n",
  );
} finally {
  rmSync(dir, { recursive: true, force: true });
}
