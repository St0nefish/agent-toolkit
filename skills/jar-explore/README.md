# jar-explore

Inspect, search, read, and decompile JAR files in the Gradle cache.

## Usage

```bash
# List all entries in a JAR
jar-explore list /path/to/artifact.jar

# Search for entries matching a pattern
jar-explore search /path/to/artifact.jar "ClassName"

# Read a file from a JAR (no extraction)
jar-explore read /path/to/artifact.jar com/example/MyClass.java

# Decompile a .class file
jar-explore decompile /path/to/artifact.jar com/example/MyClass.class

# Find JARs in Gradle cache
jar-explore find org.apache.commons commons-lang3
```