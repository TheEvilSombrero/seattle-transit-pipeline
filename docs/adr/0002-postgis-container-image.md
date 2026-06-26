# 0002 — PostGIS Container Image

**Status:** Accepted
**Date:** 2026-05-12

## Context

The project runs PostgreSQL + PostGIS in Docker for reproducibility across machines. The official PostGIS image (`postgis/postgis`) is the obvious first choice, but on this project's development machine (Apple Silicon, `arm64`) it fails at pull time:

```
no matching manifest for linux/arm64/v8 in the manifest list entries
```

Inspection of the official image's manifest confirmed that as of May 2026 the `postgis/postgis` repository on Docker Hub publishes only `linux/amd64` for every recent tag (17-3.5, 17-3.6, 18-3.6, etc.). There is no `arm64` manifest for any of them. The official PostgreSQL image (`postgres:18`) does publish multi-arch manifests, but it doesn't bundle PostGIS.

## Decision

**Use `imresamu/postgis:18-3.6` instead of `postgis/postgis:18-3.6`.**

`imresamu/postgis` is a community-maintained rebuild of the official PostGIS image that publishes manifests for both `linux/amd64` and `linux/arm64`. The interface is identical (same environment variables, same data directory layout, same extension setup); only the published architectures differ.

## Consequences

**Positives:**
- Works on Apple Silicon (arm64) without Rosetta emulation, which would impose a 3–5× performance penalty on all database operations.
- Cross-platform reproducibility — the same `docker-compose.yml` works on x86 Linux, x86 Windows (via WSL), Intel Mac, and Apple Silicon Mac. Docker pulls the appropriate architecture automatically.

**Tradeoffs:**
- Dependency on a community image rather than the official Docker Hub publication. Risk: if the maintainer stops publishing, the project is stuck on the last available tag until either a different community image fills the gap or the official image adds arm64 support.
- The community image lags official releases by hours to days. Acceptable for a portfolio project, less so for production. In the planned Phase 3 cloud deployment, managed Postgres + PostGIS services side-step this entirely.

**Documented in:** `docker-compose.yml` references this image; if a future contributor wonders why the official isn't used, this ADR explains.
