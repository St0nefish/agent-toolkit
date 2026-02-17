---
description: >-
  List entries, search, and read arbitrary files inside JARs. Use for inspecting
  JAR contents like META-INF, .properties, XML configs, manifests, and resource
  files. Do NOT use raw unzip, jar tf, or jar xf commands on JARs — use this
  instead. For class search, decompilation, and finding JARs in Gradle/Maven
  caches, use the maven-indexer MCP server (search_classes, get_class_details,
  search_artifacts).
---

# JAR Content Inspection

Use `~/.claude/tools/jar-explore/bin/jar-explore` for reading raw JAR contents. Do NOT use `unzip`, `jar tf`, or `jar xf` directly.

For **class search and decompilation**, use the **maven-indexer** MCP server instead:

- Finding classes by name → `search_classes`
- Decompiling classes to source → `get_class_details` (type: `"source"`)
- Finding JARs by coordinates → `search_artifacts`
- Finding interface implementations → `search_implementations`

This tool covers what the MCP server doesn't: listing raw entries, regex search within a JAR, and reading arbitrary non-class files.

## Subcommands

### List all entries

```bash
~/.claude/tools/jar-explore/bin/jar-explore list /path/to/file.jar
```

### Search for entries matching a pattern

```bash
~/.claude/tools/jar-explore/bin/jar-explore search /path/to/file.jar "ClassName"
~/.claude/tools/jar-explore/bin/jar-explore search /path/to/file.jar "META-INF.*\.properties"
```

Pattern is a case-insensitive extended regex.

### Read a file from a JAR (no extraction to disk)

```bash
~/.claude/tools/jar-explore/bin/jar-explore read /path/to/file.jar com/example/MyClass.java
~/.claude/tools/jar-explore/bin/jar-explore read /path/to/file.jar META-INF/MANIFEST.MF
~/.claude/tools/jar-explore/bin/jar-explore read /path/to/file.jar META-INF/spring.factories
~/.claude/tools/jar-explore/bin/jar-explore read /path/to/file.jar application.properties
```

## Typical workflow

1. Get the JAR path from maven-indexer (`search_artifacts`) or the project build output
2. Browse contents: `~/.claude/tools/jar-explore/bin/jar-explore list <jar>` or `~/.claude/tools/jar-explore/bin/jar-explore search <jar> <pattern>`
3. Read a specific file: `~/.claude/tools/jar-explore/bin/jar-explore read <jar> <entry>`

## Exit codes

- 0: Success
- 1: Bad usage / invalid arguments
- 2: File or path not found
- 3: Entry not found in JAR

## Hook auto-approval

Commands using `~/.claude/tools/jar-explore/bin/jar-explore` can be auto-approved in Claude Code hooks by matching the command prefix `~/.claude/tools/jar-explore/bin/jar-explore`. This is safe because the script is read-only (stdout output only, no disk writes).
