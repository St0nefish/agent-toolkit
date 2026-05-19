---
name: jar-explore
description: >-
  List, search, and read files inside JARs (META-INF, .properties, XML,
  manifests, resources). Use instead of raw `unzip`, `jar tf`, or `jar xf`.
  For class search and decompilation, use the maven-indexer MCP server
  bundled with this plugin.
allowed-tools: Bash, Read
---

# JAR Content Inspection

Use the plugin's bundled `jar-explore` tool for reading raw JAR contents
rather than `unzip`, `jar tf`, or `jar xf`. Do not construct plugin-root
Bash paths manually; if the current Copilot CLI session cannot resolve
the installed plugin path, say so plainly instead of guessing.

For **class search and decompilation**, use the **maven-indexer** MCP server
bundled with this plugin (run `/java-toolkit:java-toolkit start` first if
the Docker stack isn't running):

- Finding classes by name → `search_classes`
- Decompiling classes to source → `get_class_details` (type: `"source"`)
- Finding JARs by coordinates → `search_artifacts`
- Finding interface implementations → `search_implementations`

This tool covers what the MCP server doesn't: listing raw entries, regex
search within a JAR, and reading arbitrary non-class files.

## Subcommands

The tool exposes three subcommands:

- **list `<jar>`** — list every entry in the JAR.
- **search `<jar> <pattern>`** — list entries matching a case-insensitive
  extended regex (e.g. `ClassName`, `META-INF.*\.properties`).
- **read `<jar> <entry>`** — print the entry's contents to stdout (no
  extraction to disk). Use for `META-INF/MANIFEST.MF`,
  `META-INF/spring.factories`, `application.properties`, or any embedded
  source file.

## Typical workflow

1. Get the JAR path from maven-indexer (`search_artifacts`) or the project build output.
2. Browse contents: `list <jar>` or `search <jar> <pattern>`.
3. Read a specific file: `read <jar> <entry>`.

## Exit codes

- 0: Success
- 1: Bad usage / invalid arguments
- 2: File or path not found
- 3: Entry not found in JAR
