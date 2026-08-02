---
description: "Build the base image and smoke-test it (validates entrypoint, config rendering, php-fpm)"
argument-hint: "Build and smoke-test the image"
agent: "agent"
---
Build and smoke-test the image after changes to `Dockerfile`, `docker-entrypoint.sh`, or any template. This is the primary validation — there is no unit test suite; `php-fpm -t` runs at container start and exits non-zero on failure.

1. **Build**: `docker build -t php-wordpress-base .`
2. **Run detached** with the required vars (entrypoint hard-fails without `PUID`/`PGID`/`USERNAME`/`CONTAINER_NAME`):
   ```bash
   docker run -d --name phpwp-test \
     -e PUID=1000 -e PGID=1000 -e USERNAME=test -e CONTAINER_NAME=test \
     -e VOLUME_PREFIX=testwp \
     php-wordpress-base
   ```
3. **Verify**:
   - `docker ps` — container still running (an exit means the entrypoint or `php-fpm -t` failed).
   - `docker exec phpwp-test php -v` — PHP up, no fatal config errors.
   - `docker exec phpwp-test cat /usr/local/etc/php/conf.d/*.ini /etc/msmtprc` — confirm **no literal `${...}` or `$VAR` strings remain** and the expected defaults are applied.
   - `docker exec phpwp-test ls -la /run/php/` — FPM socket exists.
4. **Also test the default-fallback path**: run step 2 **without** any PHP config vars (e.g. no `APC_SHM_SIZE`) and confirm `apc.shm_size = 16M` appears in the rendered `apcu.ini` (not `${APC_SHM_SIZE}`).
5. **Clean up**: `docker rm -f phpwp-test`

Report build success/failure and each verification result. If anything fails, show the relevant log output.

See [AGENTS.md](../../AGENTS.md) for the full mental model and known pitfalls.
