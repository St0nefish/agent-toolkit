# docker-pg-query

Run PostgreSQL diagnostic queries against Docker containers without memorizing SQL.

## Usage

```bash
# List available queries
docker-pg-query --saved

# Run a saved query against a container
docker-pg-query --saved <query-name> [args...]

# Run custom SQL
docker-pg-query "SELECT ..."
```

## Saved Queries

Queries are resolved in priority order:
1. **Project**: `$GIT_ROOT/.pgquery/saved/*.sql`
2. **Global**: `$HOME/.config/pgquery/saved/*.sql`
3. **Bundled**: Shipped with the tool

- `active-queries` — Currently running queries
- `locks` — Tables with locks
- `index-usage` — Index hit rates
- `table-sizes` — Table and toast sizes
- `vacuum-stats` — VACUUM/ANALYZE status
- And more...

## Adding Project-Specific Queries

In any git repository, create queries at:

```
<repo>/.pgquery/saved/<name>.sql
```

Each file contains a single SQL query. The first line `-- description` is used as the query's description.

### Placeholders

Use `{{1}}`, `{{2}}`, etc. for parameters:

```sql
-- Find rows by status
SELECT * FROM {{1}} WHERE status = '{{2}}';
```

Run with:
```bash
docker-pg-query --saved my-query my_table active
```