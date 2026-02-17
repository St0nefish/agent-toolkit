---
description: >-
  Query PostgreSQL databases in local Docker containers. REQUIRED for all
  Docker PostgreSQL operations — do NOT use raw docker exec, psql, or SQL
  commands directly. Use when exploring tables, querying data, describing
  schemas, or debugging database contents in Docker-hosted PostgreSQL.
---

# PostgreSQL Docker Query Tool

Use `~/.claude/tools/docker-pg-query/bin/docker-pg-query` to query PostgreSQL databases running in **local Docker containers**. It runs `psql` inside the container via `docker exec` — no host-side PostgreSQL client or credentials needed.

Do NOT use raw `docker exec ... psql` commands directly — always use `~/.claude/tools/docker-pg-query/bin/docker-pg-query` instead.

**Scope**: This tool is for PostgreSQL in Docker only. It does not connect to remote databases, cloud-hosted PostgreSQL, or host-installed PostgreSQL servers.

## When to use

- The project has a PostgreSQL database running in a local Docker container
- User asks about database contents, table structure, or data
- Debugging data issues that require direct DB inspection
- Exploring what tables exist or what columns a table has

## When NOT to use

- The database is remote, cloud-hosted, or not running in Docker
- The user needs to connect to a host-installed PostgreSQL (use `psql` directly)
- There is no running Docker container with PostgreSQL

## Workflow

1. **Always start with `~/.claude/tools/docker-pg-query/bin/docker-pg-query --info`** to verify connection details are correctly discovered
2. **Explore**: Use `--tables`, `--search`, or `--saved` to understand what's available
3. **Query**: Write targeted SQL based on what you find
4. **Present results clearly**: Format output as markdown tables or summaries for the user
5. **Use CSV for large results**: Add `--csv` when results exceed ~50 rows

## Container Discovery

`~/.claude/tools/docker-pg-query/bin/docker-pg-query` automatically finds the right PostgreSQL container (in priority order):

1. CLI flag (`--container NAME`)
2. Project `.pgquery.conf` file in git root (`PGQUERY_CONTAINER=name`)
3. Docker introspection — finds running containers whose image contains `postgres` or whose name ends in `_db`/`-database`. If multiple match, prefers one matching the git root directory name.
4. Home config (`~/.config/pgquery/default.conf`)

Connects as the `postgres` superuser via local trust authentication (no credentials needed inside the container).

Use `~/.claude/tools/docker-pg-query/bin/docker-pg-query --info` to see which source provided each value.

## Subcommands

### Show connection info
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query --info
```

### Ad-hoc SQL
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query "SELECT COUNT(*) FROM my_table"
~/.claude/tools/docker-pg-query/bin/docker-pg-query --csv "SELECT * FROM my_table LIMIT 100"
```

### List all tables
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query --tables
```

### Describe a table
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query --describe my_table
```

### Search for tables/columns by name
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query --search user
~/.claude/tools/docker-pg-query/bin/docker-pg-query --search payment
```

### Saved queries
```bash
# List all saved queries
~/.claude/tools/docker-pg-query/bin/docker-pg-query --saved

# Run a saved query (no parameters)
~/.claude/tools/docker-pg-query/bin/docker-pg-query --saved table-sizes

# Run a parameterized saved query
~/.claude/tools/docker-pg-query/bin/docker-pg-query --saved count public.users
```

### Interactive psql session
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query -i
```

### Write operations (explicit opt-in)
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query --write "INSERT INTO my_table (col) VALUES ('val')"
```

### Connection overrides
```bash
~/.claude/tools/docker-pg-query/bin/docker-pg-query --container my-db "SELECT 1"
~/.claude/tools/docker-pg-query/bin/docker-pg-query --database myapp --container my-db "SELECT 1"
```

## Saved Queries

Saved queries are `.sql` files loaded from three directories (highest priority first):

1. **Project-local**: `$GIT_ROOT/.pgquery/saved/*.sql`
2. **User global**: `~/.config/pgquery/saved/*.sql`
3. **Bundled**: shipped with the tool (generic PostgreSQL queries)

If the same query name exists in multiple tiers, the higher-priority one wins.

### Writing saved queries

```sql
-- Description shown in --saved listing
-- @param 1 What the first parameter is
-- @param 2 What the second parameter is (if needed)
SELECT "column"
FROM table
WHERE "field" = '{{1}}'
  AND "other" = '{{2}}'
```

- First `--` comment = description (shown by `--saved`)
- `-- @param N` lines = parameter docs (shown when args are missing)
- `{{1}}`, `{{2}}`, ... = replaced by positional args at runtime

## Project Config File

Create `.pgquery.conf` in the git root to pin connection details:

```
PGQUERY_CONTAINER=my-app-db
PGQUERY_DATABASE=myapp
```

## Exit codes

- 0: Success
- 1: Bad usage / invalid arguments
- 3: Container not found or not running

## Safety

- **Default mode is read-only**: Only SELECT, SHOW, EXPLAIN, SET, and psql meta-commands are allowed
- **Write operations require `--write` flag**: INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, TRUNCATE
- **NEVER use `--write` without explicit user confirmation** — always ask the user before running any write operation
- **Prefer SELECT queries** — most debugging and inspection tasks only need reads

## Hook auto-approval

Read-only `~/.claude/tools/docker-pg-query/bin/docker-pg-query` commands (without `--write` or `-i`) can be safely auto-approved in Claude Code hooks by matching the command prefix `~/.claude/tools/docker-pg-query/bin/docker-pg-query`. The `--write` and `-i` flags should NOT be auto-approved.
