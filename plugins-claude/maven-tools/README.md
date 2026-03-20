# Maven Tools

MCP server for Maven Central intelligence — version lookup and dependency analysis. Runs as a persistent Docker Compose service.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/maven-tools
```

Then start the service:

```text
/maven-tools start
```

## Commands

| Command | Description |
|---------|-------------|
| `/maven-tools start` | Start the Docker Compose service |
| `/maven-tools stop` | Stop and remove the service |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| Docker | Yes | Container runtime |
| Docker Compose | Yes | Service orchestration |
