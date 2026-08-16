# Handoff Brief — Docker Installer (to the primary agent)

**From:** the Docker-installer agent · **Date:** 2026-08-11

## What shipped

The **Coqui Docker Installer** is merged and released. A single container
(`ghcr.io/carmelosantana/coqui-stack`) is now the primary install path: coqui CAP API
+ Flutter web UI in one image, behind a Caddy single-origin proxy.

- **coqui-installer** [PR #15](https://github.com/carmelosantana/coqui-installer/pull/15) — merged to `main` (`9228838`). Dockerfile (assemble-from-releases, fail-closed sha256), Caddy front (COOP/COEP + `/api/*` → `127.0.0.1:3300`), supervisord (honors the app's `POST /api/v1/server/restart` exit-10), wrapper-free `compose.yaml` (loopback-bound by default), Docker-first `install.sh` + `coqui` wrapper with native `--native` fallback, `uninstall.sh`, all PowerShell/Windows removed, Docker-first README, and CI (build + container smoke).
- **coqui-app** [PR #24](https://github.com/carmelosantana/coqui-app/pull/24) — merged; **v0.0.7** cut, publishing `Coqui-0.0.7-web.tar.gz` as a release asset (D1) so the Dockerfile fetches the web bundle by tag.
- **End-to-end verified** against real published artifacts (server 0.0.29 + app 0.0.7): `/` serves the real Flutter UI with COOP/COEP, `/api/v1/health` → `status:ok`, `restart.managed_by_launcher:true`, and `POST /api/v1/server/restart` relaunches the API process (uptime reset) while the container + Caddy stay up.
- **macOS CI** hardening: sha256sum→shasum portability, temp-file sourcing for two flaky bats tests, PyYAML-optional compose checks.

## What I'm doing next

- **In flight:** [PR #16](https://github.com/carmelosantana/coqui-installer/pull/16) merged — a **multi-arch (amd64+arm64) ghcr publish workflow** (`docker-publish.yml`). First publish is running now. ⚠️ The ghcr package is created **private** by default — it must be flipped to **public** (Packages → coqui-stack → Package settings) for `docker compose up` to pull without `docker login`.
- **Then:** confirm the published image pulls + runs on Apple Silicon, and close out installer follow-ups (branch protection to require both `test-installer` + `docker-image` checks; a couple of logged cosmetics).

## ⚠️ Needs brainstorming with you (new-agent handoff)

A real deployment gap surfaced during testing that is **out of installer scope** and needs design work in **coqui-app** (with a likely small Dockerfile/Caddy touch-point):

> In the Docker deployment the web app does **not auto-connect to the co-located server**, and there is **no way to add/modify servers in the web UI** — that server-management UI is **disabled in the web build** (it's fine for the hosted Vercel client, which has no bundled server, but it **breaks the single-container Docker UX**, where the web app should just talk to its own same-origin API at `/api/*`).

Core tension: the web build currently assumes "hosted client, server config disabled," but the Docker image ships web + server **together on one origin**, so the web app needs to (a) **default to the same-origin API** (`/api/v1`, no manual server entry) and ideally (b) **re-enable server management** in this bundled context (add/switch/restart servers) — without regressing the Vercel deployment.

**Plan:** run **`/superpowers:brainstorming`** on this problem to explore the design (build-flag/env to distinguish "bundled" vs "hosted" web builds? same-origin default in the API client? conditional server-management UI? how the installer/Dockerfile signals "bundled" to the web build?), then hand the settled design to a fresh agent via **`/anthropic-skills:prompt-agent-task`** to implement.

Relevant, already-verified facts to seed the brainstorm:
- Single origin in Docker: Caddy serves the web UI at `/` and proxies `/api/*` to `127.0.0.1:3300` (base path `/api/v1`) — no CORS, no API key needed.
- The web bundle is built `flutter build web --wasm --release --base-href /` (coqui-app `release.yml`, `build-web` job).
- Server controls already exist in the CAP API: `GET /api/v1/server/info|instance|stats`, `POST /api/v1/server/restart` (needs `COQUI_LAUNCHER_MANAGED=1`, which the image sets).
