# JAR Explore

List, search, and read files inside JARs without extraction. Model-triggered — fires when Claude needs to inspect JAR contents.

For class search and decompilation, see [maven-indexer](../maven-indexer/).

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/jar-explore
```

## Operations

| Subcommand | Description |
|------------|-------------|
| `list <jar>` | List all entries in the JAR |
| `search <jar> <pattern>` | List entries matching a case-insensitive regex |
| `read <jar> <entry>` | Print a single file from the JAR to stdout |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `jar` | Yes | JAR listing (part of JDK) |
| `unzip` | Yes | File extraction from JAR |
