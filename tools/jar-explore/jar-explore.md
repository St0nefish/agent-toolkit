---
description: >-
  Locate JARs in the Gradle cache, inspect, search, read, and decompile JAR
  files. REQUIRED for ALL operations involving JARs or the Gradle cache — do
  NOT use raw find, ls, unzip, jar, javap, or grep commands on JARs or inside
  ~/.gradle/. Use when finding dependencies or artifacts in the Gradle cache,
  investigating what's inside a JAR, reading source JARs, decompiling classes,
  or searching for classes/resources inside JARs.
---

# JAR Exploration

Use the `jar-explore` CLI tool for all JAR inspection tasks. Do NOT use raw `unzip`, `jar tf`, `jar xf`, or `javap` commands directly — always use `jar-explore` instead.

## When to use

- Investigating what's inside a dependency JAR
- Reading source files from a `-sources.jar`
- Decompiling `.class` files to understand behavior
- Finding JARs in the Gradle cache by Maven coordinates
- Searching for specific classes or resources in a JAR

## Subcommands

### List all entries
```bash
jar-explore list /path/to/file.jar
```

### Search for entries matching a pattern
```bash
jar-explore search /path/to/file.jar "ClassName"
jar-explore search /path/to/file.jar "META-INF.*\.properties"
```
Pattern is a case-insensitive extended regex.

### Read a file from a JAR (no extraction to disk)
```bash
jar-explore read /path/to/file.jar com/example/MyClass.java
jar-explore read /path/to/file.jar META-INF/MANIFEST.MF
```

### Decompile a .class file
```bash
jar-explore decompile /path/to/file.jar com/example/MyClass.class
```
Extracts to `/tmp`, runs `javap -c -p`, and cleans up automatically.

### Find JARs in Gradle cache
```bash
# List all versions of an artifact
jar-explore find org.apache.commons commons-lang3

# List JARs for a specific version
jar-explore find org.apache.commons commons-lang3 3.14.0
```
Searches `~/.gradle/caches/modules-2/files-2.1/`.

## Typical workflow

1. Find the JAR: `jar-explore find <group> <artifact>`
2. Explore contents: `jar-explore list <jar>` or `jar-explore search <jar> <pattern>`
3. Read source/config: `jar-explore read <jar> <entry>`
4. Decompile if no source: `jar-explore decompile <jar> <class-entry>`

## Exit codes

- 0: Success
- 1: Bad usage / invalid arguments
- 2: File or path not found
- 3: Entry not found in JAR

## Hook auto-approval

Commands using `jar-explore` can be auto-approved in Claude Code hooks by matching the command prefix `jar-explore`. This is safe because the script is read-only (stdout output, temp files cleaned up).
