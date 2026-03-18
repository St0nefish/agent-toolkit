# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Gradle command classifier ---

extract_gradle_command() {
  local -a tokens
  read -ra tokens <<<"$1"
  local exe="${tokens[0]}"

  REPLY=""
  REPLY_ARGS=()

  case "$exe" in
    gradle | ./gradlew | gradlew)
      REPLY="$exe"
      if ((${#tokens[@]} > 1)); then
        REPLY_ARGS=("${tokens[@]:1}")
      fi
      return 0
      ;;
  esac
  return 1
}

extract_gradle_tasks() {
  local -a args=("$@")
  local i=0 len=${#args[@]}

  while ((i < len)); do
    local token="${args[$i]}"
    case "$token" in
      -p | -g | -b | -c | -I | -S | --project-dir | --gradle-user-home | --build-file | \
        --settings-file | --init-script | --console | --warning-mode | \
        --priority | --max-workers | --include-build | --project-cache-dir | \
        --configuration | --dependency | \
        -D* | -P*)
        case "$token" in
          -D*=* | -P*=*) ((i++)) || true ;;
          -D* | -P*) ((i++)) || true ;;
          *) ((i += 2)) || true ;;
        esac
        ;;
      --project-dir=* | --gradle-user-home=* | --build-file=* | --settings-file=* | \
        --init-script=* | --console=* | --warning-mode=* | --priority=* | \
        --max-workers=* | --include-build=* | --project-cache-dir=* | \
        --configuration=* | --dependency=*)
        ((i++)) || true
        ;;
      --version | --help | -h | -? | --no-daemon | --daemon | --foreground | --gui | \
        --info | -i | --debug | -d | --warn | -w | --quiet | -q | --stacktrace | -s | \
        --full-stacktrace | -S | --scan | --no-scan | --build-cache | --no-build-cache | \
        --configuration-cache | --no-configuration-cache | --configure-on-demand | \
        --no-configure-on-demand | --continue | --dry-run | -m | --no-parallel | \
        --parallel | --offline | --refresh-dependencies | --rerun-tasks | \
        --no-rebuild | --profile | --stop | --status | --continuous | -t | \
        --write-locks | --update-locks | --no-watch-fs | --watch-fs | \
        --export-keys | --no-search-upward | -u)
        ((i++)) || true
        ;;
      -*)
        ((i++)) || true
        ;;
      *)
        echo "$token"
        ((i++)) || true
        ;;
    esac
  done
}

is_readonly_gradle_task() {
  local task="$1"
  local bare="${task##*:}"
  case "$bare" in
    tasks | help | projects | properties | dependencies | dependencyInsight | \
      buildEnvironment | components | outgoingVariants | resolvableConfigurations | \
      javaToolchains | model)
      return 0
      ;;
  esac
  return 1
}

is_local_build_gradle_task() {
  local task="$1"
  local bare="${task##*:}"
  case "$bare" in
    assemble | build | check | classes | clean | compileJava | compileKotlin | \
      compileTestJava | compileTestKotlin | jar | test | testClasses)
      return 0
      ;;
  esac
  return 1
}

check_gradle() {
  echo "$command" | perl -ne '$f=1,last if /^\s*(\.?\/?)gradlew?(\s|$)/; END{exit !$f}' || return 0

  if ! extract_gradle_command "$command"; then
    return 0
  fi

  local exe="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")

  local has_version=false has_help=false has_dry_run=false
  for arg in "${args[@]+"${args[@]}"}"; do
    case "$arg" in
      --version) has_version=true ;;
      --help | -h | -\?) has_help=true ;;
      --dry-run | -m) has_dry_run=true ;;
    esac
  done

  if [[ "$has_version" == true ]]; then
    allow "gradle --version is read-only"
    return 0
  fi
  if [[ "$has_help" == true ]]; then
    allow "gradle --help is read-only"
    return 0
  fi

  local -a tasks=()
  while IFS= read -r task; do
    [[ -n "$task" ]] && tasks+=("$task")
  done < <(extract_gradle_tasks "${args[@]+"${args[@]}"}")

  if [[ ${#tasks[@]} -eq 0 ]]; then
    allow "bare gradle invocation is read-only"
    return 0
  fi

  if [[ "$has_dry_run" == true ]]; then
    allow "gradle --dry-run is read-only"
    return 0
  fi

  for task in "${tasks[@]}"; do
    if ! is_readonly_gradle_task "$task" && ! is_local_build_gradle_task "$task"; then
      ask "gradle $task modifies build state"
      return 0
    fi
  done

  allow "gradle tasks are all local build/reporting tasks"
}
