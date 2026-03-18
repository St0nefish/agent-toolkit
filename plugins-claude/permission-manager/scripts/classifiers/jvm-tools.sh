# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- JVM tools classifier (java, javac, javap, kotlin, mvn) ---
check_jvm_tools() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    java)
      if echo "$command" | perl -ne '$f=1,last if /^\s*java\s+(-version|--version)/; END{exit !$f}'; then
        allow "java --version is read-only"
      fi
      return 0
      ;;
    javac)
      if echo "$command" | perl -ne '$f=1,last if /^\s*javac\s+(-version|--version)/; END{exit !$f}'; then
        allow "javac --version is read-only"
      fi
      return 0
      ;;
    javap)
      allow "javap is read-only"
      return 0
      ;;
    kotlin)
      if echo "$command" | perl -ne '$f=1,last if /^\s*kotlin\s+-version/; END{exit !$f}'; then
        allow "kotlin -version is read-only"
      fi
      return 0
      ;;
    mvn) ;;
    jar)
      if echo "$command" | perl -ne '$f=1,last if /^\s*jar\s+[- ]*t[vf]/; END{exit !$f}'; then
        allow "jar -tf/-tvf is read-only"
      fi
      return 0
      ;;
    *) return 0 ;;
  esac

  local -a tokens
  read -ra tokens <<<"$command"
  local subcmd="${tokens[1]:-}"

  case "$subcmd" in
    --version | -v)
      allow "mvn --version is read-only"
      ;;
    dependency:tree | help:effective-pom)
      allow "mvn $subcmd is read-only"
      ;;
    clean | compile | test | test-compile | package | verify | install)
      allow "mvn $subcmd is a local build/test operation"
      ;;
    *)
      ask "mvn $subcmd modifies build state"
      ;;
  esac
}
