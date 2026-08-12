# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

A **Docker base image for WordPress** — PHP-FPM 8.5 on Debian 13 ("Trixie"), optimized for WordPress with APCu, OPcache, igbinary, Redis, Imagick, and msmtp mail relay. It maps host users (PUID/PGID) into the container and renders all config from environment variables at container start. Published to `ghcr.io/hansvaneijsden/php-wordpress-base`. Full usage docs live in `README.md` — link to it, don't duplicate it.

## Criticality: this image is a shared production base

This image is the **shared base for many production WordPress sites**; each site's stack (in its own repository) references this image. Pushing to `main` builds & pushes `:latest` via CI — but that **does not** recreate the production containers. A change only reaches production when the running WP containers are recreated against the new image (see *Deploying a change* below); there is **no** auto-redeploy hook.

- **Backward compatibility is mandatory.** Existing sites pass their own env vars — never rely on behavior that breaks when a var is unset, and never remove/rename an env var without a migration path.
- **Changes reach production without a review step** once containers are recreated — validate locally (build + smoke test) before pushing.
- **One logical change per commit** so a bad change can be reverted cleanly.
- **This repo is public** — never commit secrets or customer-specific details; keep docs professional and in English.

## Key files

| File | Purpose |
|---|---|
| `Dockerfile` | Image definition: PHP extensions, PECL packages, config **templates** (`*.template` → rendered at runtime) |
| `docker-entrypoint.sh` | Runtime: validates env, creates the user, renders templates with `envsubst`, writes the FPM pool, starts `php-fpm` |
| `.env.example` | Canonical list of every env var the image reads. **Keep in sync** when adding/renaming vars |
| `.github/workflows/build-and-push.yml` | Builds & pushes to GHCR on `main` (→ `latest`) and `v*` tags (→ semver) |
| `.github/workflows/hadolint.yml` | Dockerfile lint (SARIF, non-failing) |
| `.github/dependabot.yml` | Daily base-image bumps (`php:8.5.8-fpm`), commit prefix `chore(deps)` |

## Build & test

```bash
# Build
docker build -t php-wordpress-base .

# Smoke-test the image (entrypoint requires these vars; it ignores CMD and starts php-fpm)
docker run -d --name smoke-test \
  -e PUID=1000 -e PGID=1000 -e USERNAME=test -e CONTAINER_NAME=test \
  php-wordpress-base
docker exec smoke-test php -v
docker rm -f smoke-test

# Compose config validation (external phpnet network required for `up`)
docker compose config
```

There is no unit test suite. Validation happens at container start: the entrypoint runs `php-fpm -t` and exits non-zero on failure. Use the smoke-test above as the primary check after changes — or the `/build-and-test` prompt ([`.github/prompts/build-and-test.prompt.md`](.github/prompts/build-and-test.prompt.md)) for a deeper check (rendered `.ini` files, FPM socket, no literal `${...}` left in the config).

## Deploying a change

Pushing to `main` builds & pushes `:latest` via CI — that alone does **not** update production. The running WP containers must be recreated against the new image; there is no auto-redeploy hook.

All WP stacks reference `:latest` and are managed by **Dockhand** (web UI on cloud, port 3001). The compose files for a stack live:
- on **cloud** (the Dockhand host): `/opt/dockhand/stacks/<host>/<stack>/`
- on the **remote hosts** (rtv / sykam / vps): `/data/stacks/<stack>/` — Dockhand runs only on cloud and manages these via the `hawser` agent (`127.0.0.1:2376`); there is **no** Dockhand container on the remote hosts.

Redeploy per host, per stack (33 WP containers use this image: cloud 29, rtv 3, sykam 1):

```bash
cd /opt/dockhand/stacks/cloud.hansvaneijsden.nl/<stack>  # remote hosts: /data/stacks/<stack>
docker compose pull php
docker compose up -d php
```

`docker compose up -d` only recreates a container when its image or config actually changed, so it is safe to loop over all `*-php` stacks on a host.

### Verify a deployed change

1. **Confirm every host is on the new image** — each container's image ID must equal the local `:latest`:
   `docker inspect <container> --format "{{.Image}}"` vs `docker image inspect ghcr.io/hansvaneijsden/php-wordpress-base:latest --format "{{.Id}}"`.
2. **Check health** — each WP container should show `Up ... (healthy)` (compose healthcheck hits the FPM `/ping` endpoint).
3. **Spot-check rendered config** in a running container — e.g. `docker exec <container> grep sendmail /usr/local/etc/php/conf.d/mail.ini` (confirms the new `sendmail_path`) and that no literal `${...}` remains.

### Verification gotchas

- `gh run watch <id>` opens a TUI (alternate buffer) that can hang the terminal — run it non-interactively: `gh run watch <id> | cat`; if it hangs, recover with `pkill -f "gh run watch"`.
- Inspect a template baked into an image without a full smoke test: `docker run --rm --entrypoint cat <image> /usr/local/etc/php/conf.d/mail.template`.
- Over SSH, `docker exec $(docker ps ...)` runs the `$(...)` substitution **locally** on the Mac — use single-quoted remote commands or hardcode container names.
- Inline `php -r '...'` over SSH breaks on quoting — pipe a script via stdin instead: `echo "$B64" | base64 -d | ssh host 'docker exec -i <container> php'`.

## How it works (mental model)

- **Config is data-driven.** The `Dockerfile` writes `*.template` files containing `${VAR}` placeholders. At container start, `docker-entrypoint.sh` runs `envsubst` to render them into real config (`/usr/local/etc/php/conf.d/*.ini`, `/etc/msmtprc`).
- **User is created at runtime** from PUID/PGID/USERNAME; FPM runs as that user.
- **FPM pool is per-container**: the pool `[www]` is renamed to `[<VOLUME_PREFIX|CONTAINER_NAME>]` and listens on `/run/php/<CONTAINER_NAME>.sock`.
- The container runs as **root** so the entrypoint can create users/chown; `php-fpm --nodaemonize --allow-to-run-as-root` drops privileges via the pool `user =` directive. Keep `--allow-to-run-as-root`.
- Container expects the external Docker network `phpnet` (subnet 172.50.0.0/24) and a static IP.

## Pitfall: `envsubst` and `${VAR:-default}` (fixed)

`envsubst` does **NOT** expand `${VAR:-default}` syntax — it copies it verbatim into the output — and it only sees **exported** variables (a non-exported shell var renders as empty). Both were verified on the CLI.

This repo hit the first issue: `apcu.template`/`opcache.template` used `${VAR:-default}`, so the literal string landed in the generated `.ini` and the defaults never applied. **Fixed** by switching templates to plain `${VAR}` and moving the defaults into `docker-entrypoint.sh` as `export VAR="${VAR:-default}"` **before** `envsubst` runs.

Rule for new templates: use plain `${VAR}` and apply defaults **before** `envsubst` in the entrypoint as `export`ed assignments. Do **not** use `${VAR:-default}` inside a template, and do **not** rely on non-exported shell vars being seen by `envsubst`. `${VAR:-default}` is fine in the entrypoint's own heredocs (shell-evaluated, not envsubst).

## Other gotchas

- `disable_functions` in `wordpress.template` is a deliberate security measure — currently `exec,passthru,shell_exec,system,popen,parse_ini_file,show_source`. History shows it flip-flopped (proc_open was re-enabled for Redis). Do **not** re-enable functions without explicit instruction.
- `envsubst` replaces **every** `$VAR`/`${VAR}` it finds — a template needing a literal `$` must escape it or generate it another way.
- The entrypoint **hard-fails** if `PUID`, `PGID`, `USERNAME`, or `CONTAINER_NAME` are missing. Every other config var has a **built-in default** (applied via `export` in the entrypoint before `envsubst` runs), so a missing var is never rendered empty.
- Runtime user/pool names come from env vars — keep messages/log paths (e.g. `/var/log/php/${CONTAINER_NAME}-error.log`) consistent with them.
- MySQL socket config is written at runtime to `/run/mysqld/mysqld.sock`.

## Conventions

- **Docs and code comments are in English.** Commit messages are English, descriptive, one logical change per commit; dependabot uses `chore(deps): ...`.
- Base PHP version is pinned (`php:8.5.8-fpm`) and bumped by dependabot — verify the image still builds and passes the smoke test when merging.
- Image tags: `latest` (main), `vX.Y.Z` (semver), `<short-sha>` (commits). Releases are `v*` tags.
- Keep `.env.example` ⇄ `README.md` ⇄ templates in sync when the env-var surface changes.
