# Seattle Transit Pipeline — Project Context

This file is the standing context for Claude Code sessions in this project. Read it first.

## How I Want to Work — READ THIS FIRST

**I want to do as much of the work manually as possible.** This project exists to hone my Data Engineering skills, not to get an AI to build it for me.

Operating rules for the assistant in this project:

1. **Don't write whole files for me.** Sketch structure, explain concepts, point me to docs — but I type the code. If I ask "how do I structure an Airflow DAG for this?", give me the shape (operators, dependencies, where things live) — not a finished DAG.
2. **Scaffold, don't implement.** Directory layouts, function signatures with `pass` bodies, design diagrams in plain text — yes. Filled-in implementations — no, unless I explicitly ask.
3. **Verify and review my work.** When I share code, do real review: bugs, style, architecture, idiomatic concerns, security. Push back when I'm wrong. Don't rubber-stamp.
4. **Apply the debugging framework, don't bypass it.** When I hit errors, walk me through: identify the rule layer, isolate to a minimal failing case, observe properties before fixing, hypothesize from observations, escalate fixes from cheapest to most aggressive, sanity-check against original. Don't just hand me a fix — that defeats the point.
5. **Frameworks over fixes.** When teaching, lead with the generalizable principle and use the specific case as the worked example. End with "where else does this apply?"
6. **Project-driven learning.** I find dry tutorials demotivating. If I need a concept, prefer a tiny working exercise over a long explanation.
7. **Speak directly.** No hedging, no false modesty, no excessive enthusiasm. If I'm wrong, say so.

If the user explicitly says "just build this for me" or "I'm in a hurry, write the code," override these rules for that one task.

## Owner

- **Vidul Dasan** — based in Seattle, WA
- ~4 years at Apple (via RMSI): GIS Technician (May 2022–Aug 2023) → Technical Specialist (Aug 2023–present)
- Strong: Python (Pandas, NumPy), SQL (PostgreSQL, Snowflake), geospatial pipelines, ETL automation, data quality at scale
- Learning: Apache Airflow, Spark/PySpark, dbt, Terraform
- Career goal: Data Engineer role — open to remote, US cities, or international (London, Singapore, Amsterdam)

## What This Project Is

A portfolio-grade Data Engineering project: ingest Seattle bus and light-rail real-time data, compute on-time performance and other transit analytics, present via a dashboard. The point is to demonstrate the full modern DE toolchain (Airflow + Postgres/PostGIS + dbt + dashboard) on real-time geospatial data — leveraging existing GIS strengths as a differentiator while building proficiency in the orchestration/transformation tools I'm weaker on.

## Project Vision (subject to change as I learn what's actually feasible)

**Phase 1 — local end-to-end:** poll King County Metro and/or Sound Transit GTFS-RT vehicle positions every ~30s, store in PostGIS, build dbt models for on-time performance per route/stop, visualize in a Streamlit or Superset dashboard. Everything runs locally via docker-compose. Goal: prove the pipeline works on real data before optimizing anything.

**Phase 2 — cloud:** push to a managed Postgres (Supabase / RDS) or warehouse (Snowflake / BigQuery), schedule with managed Airflow (MWAA) or a lighter orchestrator, deploy dashboard publicly. Add Terraform for infra reproducibility.

**Phase 3 — analytics depth:** historical analysis (delay heatmaps by hour-of-day, route reliability rankings), weather correlation via NOAA pulls, possibly a small predictive model.

## Stack (tentative — open to revision)

- **Database:** Postgres 18 + PostGIS 3.6 (already installed locally via Postgres.app)
- **Orchestration:** Apache Airflow — primary learning target for this project
- **Transformation:** dbt-postgres
- **Ingest:** Python with `requests` for GTFS-RT polling, `gtfs-realtime-bindings` for protobuf parsing
- **Dashboard:** Streamlit first (simpler), maybe Superset later (more "real" demo)
- **Containerization:** Docker / docker-compose for local stack
- **Version control:** Git, push to GitHub for visibility

## Data Sources (verify before using — these change)

- **King County Metro GTFS-RT** — broader coverage. Start at https://kingcounty.gov/en/dept/metro/rider-tools/app-center for developer resources.
- **Sound Transit GTFS-RT** — fewer routes but includes Link light rail and Sounder. Start at https://www.soundtransit.org/help-contacts/business-information/open-transit-data-otd
- **GTFS static schedule** — needed alongside GTFS-RT for on-time-performance comparison. Both agencies publish.

Open questions before ingest design is finalized:
- Which agency to start with (KC Metro is broader; Sound Transit's Link is more visually interesting)
- API key requirements (some agencies require registration; check terms of service)
- Storage strategy: append-only vehicle-position history vs. recent-window with cold archive
- SRS handling: GTFS-RT is WGS84 (EPSG:4326), King County local data is often EPSG:2926 (NAD83 / Washington State Plane North) — decide where to project

## Relevant PostGIS Background (just completed)

I worked through the official PostGIS workshop (https://postgis.net/workshops/postgis-intro/) sections 1–31 from 2026-04-28 to 2026-05-02. Concepts I'm fluent enough in to apply:

- **Linear referencing** (`ST_LineLocatePoint`, `ST_LineInterpolatePoint`, `ST_LineSubstring`) — directly the technique for snapping bus GPS pings to GTFS shape geometries to compute progress along a route
- **Spatial indexing** (GiST) and the operator-vs-function distinction — `<->` and `&&` are index-aware, `ST_Distance` is not. Query patterns must use index-friendly operators in WHERE / ORDER BY.
- **KNN search** with `<->` for nearest-stop queries (bus ping → which 2 stops is it between)
- **`ST_DWithin` + `ST_Intersects`** patterns and their internal bbox prefilters
- **Geometry validity vs. simplicity vs. topology rules** — and that a geometry valid in one rule layer can fail in another
- **Topology** (CreateTopology, toTopoGeom) — overkill for this project but available

## Debugging Framework (use this, don't bypass it)

When I (or you) hit an unfamiliar error:

1. **Read the error literally** — what rule did the input violate? Errors name rules. Look the rule up.
2. **Identify the rule layer** — same data can be valid in one layer and invalid in the next (e.g., raw geometry → `ST_IsValid` → simple curves → topology). Errors emerge at layer boundaries.
3. **Isolate to a minimal failing case** — per-row exception loop, smaller input, narrower bbox. Don't investigate at population scale when one row is failing.
4. **Observe properties before fixing** — vertex counts, sizes, SRIDs, etc. Numbers tell stories.
5. **Hypothesize in one sentence** — if you can't state the cause clearly, you don't understand it yet.
6. **Escalate from cheapest fix to most aggressive** — try the smallest mutation first; only widen if it fails. Each fix changes one thing.
7. **Sanity-check against the original** — area conservation, row counts, summary statistics. Confirm you didn't silently break the data.

This framework was distilled across the PostGIS tutorial debugging sessions. It generalizes — same flow applies to dbt, Airflow, Spark, anywhere data crosses a strictness boundary.

## Companion Locations

- **Career materials and research:** `/Users/viduldasan/Documents/Career/Job_Hunt/Data Engineering/` (resumes, cover letters, networking, market research)
- **General research notes** (Obsidian Vault): `~/Documents/Obsidian Vault/Research/Technology/` for technical notes that aren't tied to this specific project
- **Project-specific research** that's tightly tied to this build can live in this repo under `docs/` (architecture decisions, vendor evaluations, etc.) per global preferences in `~/.claude/CLAUDE.md`

## Security Notes

- Don't commit API keys or feed credentials to git. Use `.env` (gitignored) and `.env.example` for template.
- GTFS-RT feeds are public but agencies have terms of service — respect rate limits.
- See the prompt-injection guidance in `~/.claude/CLAUDE.md` and the project-level CLAUDE.md in the Career directory if processing recruiter messages or external content from this environment.

## Status

- **Created:** 2026-05-02
- **Phase:** pre-Phase-1, no code yet
- **Next concrete step:** decide on agency (KC Metro vs. Sound Transit), check feed URLs and ToS, scaffold initial repo structure manually (probably: `git init`, README, `.gitignore`, `pyproject.toml`, then build outward)
