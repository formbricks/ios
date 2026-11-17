# Tunnel hand-off: reaching a Linux server from a macOS job

GitHub's macOS runners cannot run Docker, so the Formbricks server under test runs in a Linux job
(`e2e/server/`) and a macOS job reaches it through a Cloudflare quick tunnel. The two jobs run side by
side (no `needs`), and swap small run artifacts because a job's outputs only publish when it ends.

To reuse this in another repo's iOS job (React Native, Flutter), copy `e2e/server/` and `e2e/tunnel/`
and the two jobs of `.github/workflows/e2e.yml`, then replace the macOS build and test steps.

## Protocol

Every artifact name ends in `-attempt-${{ github.run_attempt }}`, so a re-run never reads a stale one.

| Step | Job | Artifact | Content |
| --- | --- | --- | --- |
| 1 | Linux | `e2e-server-attempt-<n>` | `E2E_APP_URL=<https tunnel>`, or `E2E_SERVER_FAILED=1` if it never got there |
| 2 | macOS | `e2e-journey-done-attempt-<n>` | `E2E_JOURNEY_RESULT=<outcome of the test step>`, uploaded with `if: always()` |
| 3 | Linux | `e2e-server-verdict-attempt-<n>` | `E2E_SERVER_RESULT=<job.status>`, the job's last step, `if: always()` |

- Linux: `up.sh` → `seed.sh` → `start.sh` (writes `.state/server.env`) → upload 1 → wait for 2 →
  `assert-response.sh` → `cleanup.sh` → `stop.sh` / `down.sh` → upload 3.
- macOS: build and boot the simulator → wait for 1 (`await-artifact.sh`) → `server-url.sh` → run the
  journey with that URL → upload 2 → wait for 3 and fail unless it is `success`.

Each side fails when the other does, so "Re-run failed jobs" always re-runs both halves together.

## Wiring

- Workflow permissions: `actions: read` (each side lists the run's artifacts) and `contents: read`.
  Pass `GH_TOKEN: ${{ github.token }}` to the steps that run `await-artifact.sh`.
- Timeouts: the macOS job waits up to 1500 s for 1 (the server boot and seed) and 900 s for 3; the
  Linux job waits up to 2400 s for 2. Keep both `timeout-minutes` above the sum of their waits plus
  their own work.
- Install `cloudflared` from a pinned release with a checked SHA-256 (see the `server` job).
- The tunnel URL crosses jobs as data: `server-url.sh` only accepts a bare `https://` origin, and
  `kv_get` reads `KEY=value` lines without sourcing the file.
- Fork PRs have no secrets (no Enterprise license), so the calling workflow skips the whole E2E
  workflow for them and `PR Check Summary` allows that skip.
