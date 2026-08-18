#!/usr/bin/env bash
#
# flow project env — environment resolution & selection
# Part of Flow Terminal Phase 3B
#

set -Eeuo pipefail

# Resolve script directory (follows symlinks)
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
    _dir="$(cd -P "$(dirname "$_source")" >/dev/null 2>&1 && pwd)"
    _source="$(readlink "$_source")"
    [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_source")" >/dev/null 2>&1 && pwd)"
unset _source _dir

SCRIPT_VERSION="1.0.0"
SCHEMA_VERSION=1

# Colors
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[31m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_BLUE='\033[34m'
    C_MAGENTA='\033[35m'
    C_CYAN='\033[36m'
else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN=''
fi

JSON_OUTPUT=false
VERBOSE=false

# XDG paths
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PROJECT_STATE_DIR="$XDG_STATE_HOME/flow/projects"

# Lock file for atomic writes
LOCK_DIR="$PROJECT_STATE_DIR/.locks"

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

print_human() { [[ "$JSON_OUTPUT" == false ]] && printf '%b\n' "$*"; }
print_json() { [[ "$JSON_OUTPUT" == true ]] && printf '%s\n' "$*"; }

# Get project ID from root path (deterministic hash)
project_id_from_root() {
    local root="$1"
    printf '%s' "$root" | sha256sum | cut -c1-16
}

# Get project state file path
project_state_file() {
    local root="$1"
    local id
    id=$(project_id_from_root "$root")
    printf '%s/%s.json' "$PROJECT_STATE_DIR" "$id"
}

# Ensure state directory exists
ensure_state_dir() {
    mkdir -p "$PROJECT_STATE_DIR"
    mkdir -p "$LOCK_DIR"
}

# Get project root using Phase 2 detector logic
get_project_root() {
    local git_root=""
    if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        printf '%s\n' "$git_root"
        return 0
    fi

    local dir="$PWD"
    local markers=(
        "pyproject.toml" "package.json" "go.mod" "Cargo.toml"
        "composer.json" "Gemfile" "pom.xml" "build.gradle" "build.gradle.kts"
        "mix.exs" "CMakeLists.txt" "Makefile" "Taskfile.yml" "Justfile"
        "Dockerfile" "Containerfile" "compose.yaml" "compose.yml"
        "docker-compose.yml" "docker-compose.yaml" "Chart.yaml"
        "kustomization.yaml" "ansible.cfg" "*.csproj" "*.sln"
        "pubspec.yaml" "Package.swift" "stack.yaml" "dune-project"
        ".github" "terraform"
    )

    while [[ "$dir" != "/" ]]; do
        for marker in "${markers[@]}"; do
            if [[ "$marker" == *'*'* ]]; then
                compgen -G "$dir/$marker" >/dev/null 2>&1 && { printf '%s\n' "$dir"; return 0; }
            elif [[ -e "$dir/$marker" ]]; then
                printf '%s\n' "$dir"; return 0
            fi
        done
        dir="$(dirname "$dir")"
    done
    printf '%s\n' "$PWD"
    return 1
}

# Get project name from root
get_project_name() {
    local root="$1"
    local git_root="$2"

    if [[ -n "$git_root" && "$git_root" == "$root" ]]; then
        basename "$git_root"
        return
    fi

    if [[ -f "$root/package.json" ]]; then
        grep -E '"name"\s*:' "$root/package.json" 2>/dev/null | head -1 | sed -E 's/.*:\s*"([^"]+)".*/\1/' | xargs
        return
    fi
    if [[ -f "$root/pyproject.toml" ]]; then
        grep -E '^name\s*=' "$root/pyproject.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"?([^"]+)"?/\1/' | xargs
        return
    fi
    if [[ -f "$root/Cargo.toml" ]]; then
        grep -E '^name\s*=' "$root/Cargo.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' | xargs
        return
    fi

    basename "$root"
}

# Load project state
load_project_state() {
    local state_file="$1"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        printf '{}'
    fi
}

# Save project state atomically
save_project_state() {
    local state_file="$1"
    local state_json="$2"
    local tmp_file
    tmp_file=$(mktemp "${state_file}.tmp.XXXXXX")
    printf '%s\n' "$state_json" > "$tmp_file"
    mv "$tmp_file" "$state_file"
}

# Acquire lock for project state
acquire_lock() {
    local state_file="$1"
    local lock_file="$LOCK_DIR/$(basename "$state_file" .json).lock"
    mkdir -p "$LOCK_DIR"
    exec 200>"$lock_file"
    flock -x 200
}

release_lock() {
    flock -u 200 2>/dev/null || true
    exec 200>&-
}

# Get project context
get_project_context() {
    local root name git_root
    root=$(get_project_root)
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    name=$(get_project_name "$root" "$git_root")
    printf '%s|%s|%s\n' "$root" "$name" "$git_root"
}

# Validate Python environment
validate_python_env() {
    local env_path="$1"
    local python_bin="$env_path/bin/python"
    [[ -x "$python_bin" ]] || return 1
    # Get version if possible
    local version
    version=$("$python_bin" --version 2>/dev/null | sed 's/Python //')
    printf '%s' "$version"
    return 0
}

# Discover Python environments in project/profile scope
discover_python_envs() {
    local root="$1"
    local scope="$2"

    local search_dir="$root"
    if [[ "$scope" != "." ]]; then
        search_dir="$root/$scope"
    fi

    local candidates=()
    local env_dirs=(".venv" "venv" "env")

    for env_dir in "${env_dirs[@]}"; do
        local full_path="$search_dir/$env_dir"
        if [[ -d "$full_path" ]]; then
            local version
            version=$(validate_python_env "$full_path" 2>/dev/null || printf 'unknown')
            local rel_path
            if [[ "$scope" != "." ]]; then
                rel_path="$scope/$env_dir"
            else
                rel_path="$env_dir"
            fi
            candidates+=("existing|$rel_path|$version")
        fi
    done

    printf '%s\n' "${candidates[@]}"
}

# Discover Node environments
discover_node_envs() {
    local root="$1"
    local scope="$2"

    local search_dir="$root"
    if [[ "$scope" != "." ]]; then
        search_dir="$root/$scope"
    fi

    local candidates=()

    # Check for .nvmrc or .node-version
    if [[ -f "$search_dir/.nvmrc" ]]; then
        local version
        version=$(cat "$search_dir/.nvmrc" 2>/dev/null | xargs)
        local rel_path
        if [[ "$scope" != "." ]]; then
            rel_path="$scope/.nvmrc"
        else
            rel_path=".nvmrc"
        fi
        candidates+=("nvm|$rel_path|$version")
    fi

    if [[ -f "$search_dir/.node-version" ]]; then
        local version
        version=$(cat "$search_dir/.node-version" 2>/dev/null | xargs)
        local rel_path
        if [[ "$scope" != "." ]]; then
            rel_path="$scope/.node-version"
        else
            rel_path=".node-version"
        fi
        candidates+=("node-version|$rel_path|$version")
    fi

    # Check for node_modules (existing but not a full env)
    if [[ -d "$search_dir/node_modules" ]]; then
        local rel_path
        if [[ "$scope" != "." ]]; then
            rel_path="$scope/node_modules"
        else
            rel_path="node_modules"
        fi
        candidates+=("existing|$rel_path|system Node")
    fi

    printf '%s\n' "${candidates[@]}"
}

# Discover runtime hints from project files
discover_runtime_hints() {
    local root="$1"
    local scope="$2"

    local search_dir="$root"
    if [[ "$scope" != "." ]]; then
        search_dir="$root/$scope"
    fi

    local hints=()

    # Python hints
    [[ -f "$search_dir/pyproject.toml" ]] && hints+=("pyproject.toml")
    [[ -f "$search_dir/uv.lock" ]] && hints+=("uv.lock")
    [[ -f "$search_dir/requirements.txt" ]] && hints+=("requirements.txt")
    [[ -f "$search_dir/Pipfile" ]] && hints+=("Pipfile")
    [[ -f "$search_dir/poetry.lock" ]] && hints+=("poetry.lock")
    [[ -f "$search_dir/.python-version" ]] && hints+=(".python-version")

    # Node hints
    [[ -f "$search_dir/package.json" ]] && hints+=("package.json")
    [[ -f "$search_dir/package-lock.json" ]] && hints+=("package-lock.json")
    [[ -f "$search_dir/pnpm-lock.yaml" ]] && hints+=("pnpm-lock.yaml")
    [[ -f "$search_dir/yarn.lock" ]] && hints+=("yarn.lock")
    [[ -f "$search_dir/bun.lock" ]] && hints+=("bun.lock")

    # Mise/asdf
    [[ -f "$search_dir/mise.toml" ]] && hints+=("mise.toml")
    [[ -f "$search_dir/.tool-versions" ]] && hints+=(".tool-versions")

    printf '%s\n' "${hints[@]}"
}

# Rank Python environment candidates
rank_python_candidates() {
    local scope="$1"
    local -n cand_ref=$2

    local ranked=()

    # 1. Existing env matching profile scope exactly
    for c in "${cand_ref[@]}"; do
        IFS='|' read -r strategy path version cand_scope <<< "$c"
        if [[ "$strategy" == "existing" && "$cand_scope" == "$scope" ]]; then
            ranked+=("$c|high|scope match")
        fi
    done

    # 2. Existing .venv at project/profile root
    for c in "${cand_ref[@]}"; do
        IFS='|' read -r strategy path version cand_scope <<< "$c"
        if [[ "$strategy" == "existing" && "$path" == *.venv ]]; then
            ranked+=("$c|high|.venv preferred")
        fi
    done

    # 3. Existing venv at project/profile root
    for c in "${cand_ref[@]}"; do
        IFS='|' read -r strategy path version cand_scope <<< "$c"
        if [[ "$strategy" == "existing" && "$path" == *venv && "$path" != *.venv ]]; then
            ranked+=("$c|medium|venv")
        fi
    done

    # 4. uv candidate if uv.lock exists
    local has_uv_lock=false
    for hint in "${hints[@]}"; do
        [[ "$hint" == "uv.lock" ]] && has_uv_lock=true
    done
    if [[ "$has_uv_lock" == true ]]; then
        ranked+=("uv||uv available|medium|uv.lock present")
    fi

    # 5. mise candidate if mise.toml/.tool-versions exists
    local has_mise=false
    for hint in "${hints[@]}"; do
        [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && has_mise=true
    done
    if [[ "$has_mise" == true ]]; then
        ranked+=("mise||mise available|medium|mise config present")
    fi

    # 6. system Python
    ranked+=("system||system Python|low|system Python")

    # 7. none
    ranked+=("none||none|low|no environment")

    printf '%s\n' "${ranked[@]}"
}

# Rank Node environment candidates
rank_node_candidates() {
    local scope="$1"
    local -n cand_ref=$2

    local ranked=()

    # 1. Version file matching scope
    for c in "${cand_ref[@]}"; do
        IFS='|' read -r strategy path version cand_scope <<< "$c"
        if [[ ("$strategy" == "nvm" || "$strategy" == "node-version") && "$cand_scope" == "$scope" ]]; then
            ranked+=("$c|high|version file matches scope")
        fi
    done

    # 2. Existing node_modules
    for c in "${cand_ref[@]}"; do
        IFS='|' read -r strategy path version cand_scope <<< "$c"
        if [[ "$strategy" == "existing" ]]; then
            ranked+=("$c|medium|existing node_modules")
        fi
    done

    # 3. mise
    local has_mise=false
    for hint in "${hints[@]}"; do
        [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && has_mise=true
    done
    if [[ "$has_mise" == true ]]; then
        ranked+=("mise||mise available|medium|mise config present")
    fi

    # 4. system Node
    ranked+=("system||system Node|low|system Node")

    # 5. none
    ranked+=("none||none|low|no environment")

    printf '%s\n' "${ranked[@]}"
}

# Rank Go candidates
rank_go_candidates() {
    local scope="$1"
    local -n cand_ref=$2

    local ranked=()

    local has_mise=false
    for hint in "${hints[@]}"; do
        [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && has_mise=true
    done
    if [[ "$has_mise" == true ]]; then
        ranked+=("mise||mise available|medium|mise config present")
    fi

    ranked+=("system||system Go|low|system Go")
    ranked+=("none||none|low|no environment")

    printf '%s\n' "${ranked[@]}"
}

# Rank Rust candidates
rank_rust_candidates() {
    local scope="$1"
    local -n cand_ref=$2

    local ranked=()

    local has_mise=false
    for hint in "${hints[@]}"; do
        [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && has_mise=true
    done
    if [[ "$has_mise" == true ]]; then
        ranked+=("mise||mise available|medium|mise config present")
    fi

    ranked+=("system||system Rust|low|system Rust")
    ranked+=("none||none|low|no environment")

    printf '%s\n' "${ranked[@]}"
}

# Rank generic candidates (infrastructure, etc.)
rank_generic_candidates() {
    local scope="$1"
    local -n cand_ref=$2

    local ranked=()

    local has_mise=false
    for hint in "${hints[@]}"; do
        [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && has_mise=true
    done
    if [[ "$has_mise" == true ]]; then
        ranked+=("mise|mise|mise available")
    fi

    ranked+=("system|system|system runtime")
    ranked+=("none|none|no environment")

    printf '%s\n' "${ranked[@]}"
}

# Discover languages within profile scope
discover_languages_in_scope() {
    local root="$1"
    local scope="$2"

    local search_dir="$root"
    if [[ "$scope" != "." ]]; then
        search_dir="$root/$scope"
    fi

    local languages=()

    # Python markers
    if [[ -f "$search_dir/manage.py" ]] || [[ -f "$search_dir/pyproject.toml" ]] || \
       [[ -f "$search_dir/requirements.txt" ]] || [[ -d "$search_dir/requirements" ]] || \
       [[ -f "$search_dir/Pipfile" ]] || [[ -f "$search_dir/poetry.lock" ]] || \
       [[ -f "$search_dir/setup.py" ]] || [[ -f "$search_dir/setup.cfg" ]] || \
       [[ -f "$search_dir/uv.lock" ]] || [[ -f "$search_dir/.python-version" ]]; then
        languages+=("python")
    fi

    # Node/JavaScript markers
    if [[ -f "$search_dir/package.json" ]]; then
        languages+=("javascript")
        if [[ -f "$search_dir/tsconfig.json" ]]; then
            languages+=("typescript")
        fi
    fi

    # Go markers
    if [[ -f "$search_dir/go.mod" ]]; then
        languages+=("go")
    fi

    # Rust markers
    if [[ -f "$search_dir/Cargo.toml" ]]; then
        languages+=("rust")
    fi

    # Java markers
    if [[ -f "$search_dir/pom.xml" ]] || [[ -f "$search_dir/build.gradle" ]] || [[ -f "$search_dir/build.gradle.kts" ]]; then
        languages+=("java")
    fi

    # PHP markers
    if [[ -f "$search_dir/composer.json" ]]; then
        languages+=("php")
    fi

    # Ruby markers
    if [[ -f "$search_dir/Gemfile" ]]; then
        languages+=("ruby")
    fi

    # Terraform/OpenTofu markers
    if compgen -G "$search_dir/*.tf" >/dev/null 2>&1 || compgen -G "$search_dir/*.tf.json" >/dev/null 2>&1; then
        languages+=("terraform")
    fi

    # Python env markers (even without project files)
    if [[ -d "$search_dir/.venv" ]] || [[ -d "$search_dir/venv" ]] || [[ -d "$search_dir/env" ]]; then
        languages+=("python")
    fi

    # Node env markers
    if [[ -d "$search_dir/node_modules" ]] || [[ -f "$search_dir/.nvmrc" ]] || [[ -f "$search_dir/.node-version" ]]; then
        languages+=("javascript")
    fi

    printf '%s\n' "${languages[@]}"
}

# Get project root and state file
get_project_state() {
    local project_context root name git_root
    project_context=$(get_project_context)
    IFS='|' read -r root name git_root <<< "$project_context"
    local state_file
    state_file=$(project_state_file "$root")
    printf '%s|%s|%s|%s\n' "$root" "$name" "$git_root" "$state_file"
}

# List environment candidates for a profile
cmd_list() {
    local profile_name="${1:-}"
    [[ -n "$profile_name" ]] || { print_human "${C_RED}Profile name required${C_RESET}"; print_help; return 1; }

    local project_state root name git_root state_file
    project_state=$(get_project_state)
    IFS='|' read -r root name git_root state_file <<< "$project_state"

    ensure_state_dir
    acquire_lock "$state_file"

    local state_json
    state_json=$(load_project_state "$state_file")
    release_lock

    # Get profile
    local profile_json
    profile_json=$(printf '%s' "$state_json" | jq -r ".profiles[\"$profile_name\"] // empty")
    [[ -n "$profile_json" ]] || { print_human "${C_RED}Profile '$profile_name' does not exist.${C_RESET}"; return 1; }

    local profile_type profile_scope
    profile_type=$(printf '%s' "$profile_json" | jq -r '.type // "custom"')
    profile_scope=$(printf '%s' "$profile_json" | jq -r '.scope // "."')

    # Get detector output
    local detect_json
    detect_json=$("$SCRIPT_DIR/detect.sh" --json 2>/dev/null || printf '{}')

    # Discover languages in profile scope (independent of root detector)
    local scope_languages=()
    mapfile -t scope_languages < <(discover_languages_in_scope "$root" "$profile_scope")

    # Discover candidates based on detected languages in scope
    local python_candidates=()
    local node_candidates=()
    local hints=()

    # Get hints for this scope
    local search_dir="$root"
    if [[ "$profile_scope" != "." ]]; then
        search_dir="$root/$profile_scope"
    fi

    mapfile -t hints < <(discover_runtime_hints "$root" "$profile_scope")

    # Python candidates
    for lang in "${scope_languages[@]}"; do
        if [[ "$lang" == "python" ]]; then
            mapfile -t python_candidates < <(discover_python_envs "$root" "$profile_scope")
            # Also add uv if available
            for hint in "${hints[@]}"; do
                [[ "$hint" == "uv.lock" ]] && python_candidates+=("uv|uv|uv available")
                [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && python_candidates+=("mise|mise|mise available")
            done
            python_candidates+=("system|system|system Python")
            python_candidates+=("none|none|none")
            break
        fi
    done

    # Node candidates
    for lang in "${scope_languages[@]}"; do
        if [[ "$lang" == "javascript" ]] || [[ "$lang" == "typescript" ]]; then
            mapfile -t node_candidates < <(discover_node_envs "$root" "$profile_scope")
            for hint in "${hints[@]}"; do
                [[ "$hint" == "mise.toml" || "$hint" == ".tool-versions" ]] && node_candidates+=("mise|mise|mise available")
            done
            node_candidates+=("system|system|system Node")
            node_candidates+=("none|none|none")
            break
        fi
    done

    # Generic candidates for other languages (Go, Rust, Terraform, Java, PHP, Ruby, etc.)
    local generic_candidates=()
    for lang in "${scope_languages[@]}"; do
        case "$lang" in
            python|javascript|typescript) continue ;;
            go|rust|java|php|ruby|terraform|swift|dart|elixir|haskell|ocaml|cpp|csharp)
                local ranked
                mapfile -t ranked < <(rank_generic_candidates "$profile_scope" generic_candidates)
                for r in "${ranked[@]}"; do
                    generic_candidates+=("$r")
                done
                break
                ;;
        esac
    done

    if [[ "$JSON_OUTPUT" == true ]]; then
        local output
        # Convert candidates arrays to JSON - handle empty arrays
        local python_json node_json generic_json
        if [[ ${#python_candidates[@]} -gt 0 ]]; then
            python_json=$(printf '%s\n' "${python_candidates[@]}" | jq -R 'split("|") | {strategy: .[0], target: .[1], version: .[2]}' | jq -s '.')
        else
            python_json='[]'
        fi
        if [[ ${#node_candidates[@]} -gt 0 ]]; then
            node_json=$(printf '%s\n' "${node_candidates[@]}" | jq -R 'split("|") | {strategy: .[0], target: .[1], version: .[2]}' | jq -s '.')
        else
            node_json='[]'
        fi
        if [[ ${#generic_candidates[@]} -gt 0 ]]; then
            generic_json=$(printf '%s\n' "${generic_candidates[@]}" | jq -R 'split("|") | {strategy: .[0], target: .[1], version: .[2]}' | jq -s '.')
        else
            generic_json='[]'
        fi
        output=$(jq -n \
            --arg profile_name "$profile_name" \
            --arg profile_type "$profile_type" \
            --arg profile_scope "$profile_scope" \
            --argjson detect "$detect_json" \
            --argjson python "$python_json" \
            --argjson node "$node_json" \
            --argjson generic "$generic_json" \
            '{
                project: $detect.project,
                profile: {name: $profile_name, type: $profile_type, scope: $profile_scope},
                detection: $detect,
                candidates: {python: $python, node: $node, generic: $generic}
            }')
        printf '%s\n' "$output"
        return
    fi

    print_human "${C_BOLD}${C_CYAN}Flow Environment Candidates${C_RESET}"
    print_human "${C_DIM}────────────────────────────────────────${C_RESET}"
    print_human ""
    print_human "Profile:"
    print_human "  $profile_name"
    print_human "  type: $profile_type"
    print_human "  scope: $profile_scope"
    print_human ""

    # Detected languages
    local lang_names
    lang_names=$(printf '%s' "$detect_json" | jq -r '.languages[].name' 2>/dev/null | sort -u | paste -sd ", " -)
    if [[ -n "$lang_names" ]]; then
        print_human "Detected:"
        print_human "  $lang_names"
        print_human ""
    fi

    # Python candidates
    if [[ ${#python_candidates[@]} -gt 0 ]]; then
        print_human "Python Candidates:"
        local i=1
        for c in "${python_candidates[@]}"; do
            IFS='|' read -r strategy path version <<< "$c"
            local status="available"
            [[ "$strategy" == "existing" ]] && status="ready"
            local recommended=""
            [[ $i -eq 1 ]] && recommended=" ${C_GREEN}[recommended]${C_RESET}"
            print_human "  $i. ${C_GREEN}●${C_RESET} $path${recommended}"
            print_human "     strategy: $strategy"
            [[ -n "$version" && "$version" != "" ]] && print_human "     version: $version"
            print_human "     status: $status"
            print_human ""
            ((i++))
        done
    fi

    # Node candidates
    if [[ ${#node_candidates[@]} -gt 0 ]]; then
        print_human "Node Candidates:"
        local i=1
        for c in "${node_candidates[@]}"; do
            IFS='|' read -r strategy path version <<< "$c"
            local status="available"
            [[ "$strategy" == "existing" || "$strategy" == "nvm" || "$strategy" == "node-version" ]] && status="ready"
            local recommended=""
            [[ $i -eq 1 ]] && recommended=" ${C_GREEN}[recommended]${C_RESET}"
            print_human "  $i. ${C_GREEN}●${C_RESET} $path${recommended}"
            print_human "     strategy: $strategy"
            [[ -n "$version" && "$version" != "" ]] && print_human "     version: $version"
            print_human "     status: $status"
            print_human ""
            ((i++))
        done
    fi

    if [[ ${#python_candidates[@]} -eq 0 && ${#node_candidates[@]} -eq 0 && ${#generic_candidates[@]} -eq 0 ]]; then
        print_human "  ${C_DIM}No environment candidates for detected languages${C_RESET}"
        print_human ""
    fi

    # Generic candidates
    if [[ ${#generic_candidates[@]} -gt 0 ]]; then
        print_human "Other Candidates:"
        local i=1
        for c in "${generic_candidates[@]}"; do
            IFS='|' read -r strategy path version <<< "$c"
            local status="available"
            local recommended=""
            [[ $i -eq 1 ]] && recommended=" ${C_GREEN}[recommended]${C_RESET}"
            print_human "  $i. ${C_GREEN}●${C_RESET} ${path:-$strategy}${recommended}"
            print_human "     strategy: $strategy"
            [[ -n "$version" && "$version" != "" ]] && print_human "     version: $version"
            print_human "     status: $status"
            print_human ""
            ((i++))
        done
    fi

    # Saved environment
    local saved_strategy saved_target
    saved_strategy=$(printf '%s' "$profile_json" | jq -r '.environment.strategy // "unconfigured"')
    saved_target=$(printf '%s' "$profile_json" | jq -r '.environment.target // ""')

    print_human "Saved:"
    if [[ "$saved_strategy" == "unconfigured" || -z "$saved_target" ]]; then
        print_human "  ${C_DIM}none${C_RESET}"
    else
        print_human "  strategy: $saved_strategy"
        print_human "  target: $saved_target"
    fi
    print_human ""
}

# Show current environment for a profile
cmd_show() {
    local profile_name="${1:-}"
    [[ -n "$profile_name" ]] || { print_human "${C_RED}Profile name required${C_RESET}"; print_help; return 1; }

    local project_state root name git_root state_file
    project_state=$(get_project_state)
    IFS='|' read -r root name git_root state_file <<< "$project_state"

    ensure_state_dir
    acquire_lock "$state_file"

    local state_json
    state_json=$(load_project_state "$state_file")
    release_lock

    local profile_json
    profile_json=$(printf '%s' "$state_json" | jq -r ".profiles[\"$profile_name\"] // empty")
    [[ -n "$profile_json" ]] || { print_human "${C_RED}Profile '$profile_name' does not exist.${C_RESET}"; return 1; }

    if [[ "$JSON_OUTPUT" == true ]]; then
        printf '%s\n' "$profile_json"
        return
    fi

    local profile_type profile_scope saved_strategy saved_target saved_auto
    profile_type=$(printf '%s' "$profile_json" | jq -r '.type // "custom"')
    profile_scope=$(printf '%s' "$profile_json" | jq -r '.scope // "."')
    saved_strategy=$(printf '%s' "$profile_json" | jq -r '.environment.strategy // "unconfigured"')
    saved_target=$(printf '%s' "$profile_json" | jq -r '.environment.target // ""')
    saved_auto=$(printf '%s' "$profile_json" | jq -r '.environment.auto_activate // false')

    print_human "${C_BOLD}${C_CYAN}Flow Environment Status${C_RESET}"
    print_human "${C_DIM}────────────────────────────────────────${C_RESET}"
    print_human ""
    print_human "Profile:"
    print_human "  $profile_name"
    print_human "  type: $profile_type"
    print_human "  scope: $profile_scope"
    print_human ""
    print_human "Environment:"
    print_human "  strategy: $saved_strategy"
    [[ -n "$saved_target" && "$saved_target" != "null" ]] && print_human "  target: $saved_target"
    print_human "  auto_activate: $saved_auto"
    print_human ""

    # Validate saved target
    if [[ "$saved_strategy" == "existing" && -n "$saved_target" && "$saved_target" != "null" ]]; then
        local target_path="$root/$saved_target"
        if [[ -d "$target_path" ]]; then
            print_human "${C_GREEN}Status: ready${C_RESET}"
            # Check Python version if applicable
            if [[ -x "$target_path/bin/python" ]]; then
                local version
                version=$("$target_path/bin/python" --version 2>/dev/null)
                print_human "  $version"
            fi
        else
            print_human "${C_RED}Status: MISSING${C_RESET}"
            print_human "  Target directory no longer exists: $saved_target"
        fi
    elif [[ "$saved_strategy" == "unconfigured" ]]; then
        print_human "${C_YELLOW}Status: not configured${C_RESET}"
    else
        print_human "${C_DIM}Status: $saved_strategy${C_RESET}"
    fi
}

# Set environment for a profile
cmd_set() {
    local profile_name="${1:-}"
    shift || true
    [[ -n "$profile_name" ]] || { print_human "${C_RED}Profile name required${C_RESET}"; print_help; return 1; }

    local strategy=""
    local target=""
    local auto_activate=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy) strategy="$2"; shift 2 ;;
            --target) target="$2"; shift 2 ;;
            --auto-activate) auto_activate=true; shift ;;
            *) print_human "${C_RED}Unknown option: $1${C_RESET}"; return 1 ;;
        esac
    done

    [[ -n "$strategy" ]] || { print_human "${C_RED}--strategy required${C_RESET}"; return 1; }

    local project_state root name git_root state_file
    project_state=$(get_project_state)
    IFS='|' read -r root name git_root state_file <<< "$project_state"

    ensure_state_dir
    acquire_lock "$state_file"

    local state_json
    state_json=$(load_project_state "$state_file")

    local profile_json
    profile_json=$(printf '%s' "$state_json" | jq -r ".profiles[\"$profile_name\"] // empty")
    [[ -n "$profile_json" ]] || { print_human "${C_RED}Profile '$profile_name' does not exist.${C_RESET}"; release_lock; return 1; }

    # Validate strategy
    case "$strategy" in
        existing)
            [[ -n "$target" ]] || { print_human "${C_RED}--target required for existing strategy${C_RESET}"; release_lock; return 1; }
            local target_path="$root/$target"
            [[ -d "$target_path" ]] || { print_human "${C_RED}Target does not exist: $target${C_RESET}"; release_lock; return 1; }
            # Validate it's a valid environment
            if [[ -x "$target_path/bin/python" ]] || [[ -x "$target_path/bin/node" ]] || [[ -d "$target_path/node_modules" ]]; then
                : # valid
            else
                print_human "${C_RED}Target is not a valid environment: $target${C_RESET}"; release_lock; return 1
            fi
            ;;
        uv|mise|venv|system|none|nvm|node-version)
            # These are intent declarations, no target validation needed
            target=""
            ;;
        *)
            print_human "${C_RED}Invalid strategy: $strategy${C_RESET}"; release_lock; return 1
            ;;
    esac

    # Update profile environment
    local env_json
    env_json=$(jq -n \
        --arg strategy "$strategy" \
        --arg target "$target" \
        --argjson auto "$auto_activate" \
        '{strategy: $strategy, target: $target, auto_activate: $auto}')

    state_json=$(printf '%s' "$state_json" | jq --arg name "$profile_name" --argjson env "$env_json" '.profiles[$name].environment = $env')

    save_project_state "$state_file" "$state_json"
    release_lock

    if [[ "$JSON_OUTPUT" == true ]]; then
        jq -n \
            --arg name "$profile_name" \
            --arg strategy "$strategy" \
            --arg target "$target" \
            --argjson auto "$auto_activate" \
            '{saved: true, profile: $name, environment: {strategy: $strategy, target: $target, auto_activate: $auto}}'
    else
        print_human "${C_GREEN}Environment set for '$profile_name'${C_RESET}"
        print_human "  strategy: $strategy"
        [[ -n "$target" ]] && print_human "  target: $target"
        print_human "  auto_activate: $auto_activate"
    fi
}

# Clear environment for a profile
cmd_clear() {
    local profile_name="${1:-}"
    [[ -n "$profile_name" ]] || { print_human "${C_RED}Profile name required${C_RESET}"; print_help; return 1; }

    local project_state root name git_root state_file
    project_state=$(get_project_state)
    IFS='|' read -r root name git_root state_file <<< "$project_state"

    ensure_state_dir
    acquire_lock "$state_file"

    local state_json
    state_json=$(load_project_state "$state_file")

    local profile_json
    profile_json=$(printf '%s' "$state_json" | jq -r ".profiles[\"$profile_name\"] // empty")
    [[ -n "$profile_json" ]] || { print_human "${C_RED}Profile '$profile_name' does not exist.${C_RESET}"; release_lock; return 1; }

    # Reset to unconfigured
    local env_json
    env_json=$(jq -n '{strategy: "unconfigured", target: null, auto_activate: false}')

    state_json=$(printf '%s' "$state_json" | jq --arg name "$profile_name" --argjson env "$env_json" '.profiles[$name].environment = $env')

    save_project_state "$state_file" "$state_json"
    release_lock

    print_human "${C_GREEN}Environment cleared for '$profile_name'${C_RESET}"
}

print_help() {
    cat <<'EOF'
flow project profile env — environment resolution & selection

USAGE:
    flow project profile env <subcommand> [options]

SUBCOMMANDS:
    list <profile>        List environment candidates for a profile
    show <profile>        Show current environment for a profile
    set <profile>         Set environment for a profile
    clear <profile>       Clear environment for a profile

OPTIONS:
    --json               Emit JSON output
    -v, --verbose        Verbose output
    -h, --help           Show this help
    --version            Show version

SET OPTIONS:
    --strategy STRATEGY  existing|uv|mise|venv|system|none
    --target PATH        Target path (required for existing)
    --auto-activate      Enable auto-activation (Phase 3C)

EXAMPLES:
    flow project profile env list backend
    flow project profile env show backend
    flow project profile env set backend --strategy existing --target backend/.venv
    flow project profile env set frontend --strategy system
    flow project profile env clear backend

ENVIRONMENT STRATEGIES:
    existing    Use existing virtual environment (--target required)
    uv          Use uv for environment management
    mise        Use mise for runtime management
    venv        Use python -m venv
    system      Use system runtime
    none        No automatic environment
EOF
}

main() {
    local args=()
    local subcmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) JSON_OUTPUT=true ;;
            -v|--verbose) VERBOSE=true ;;
            -h|--help) print_help; exit 0 ;;
            --version) printf 'env.sh %s (schema %s)\n' "$SCRIPT_VERSION" "$SCHEMA_VERSION"; exit 0 ;;
            *)
                if [[ -z "$subcmd" ]]; then
                    subcmd="$1"
                else
                    args+=("$1")
                fi
                ;;
        esac
        shift
    done

    subcmd="${subcmd:-list}"

    case "$subcmd" in
        list)
            cmd_list "${args[@]}"
            ;;
        show)
            cmd_show "${args[@]}"
            ;;
        set)
            cmd_set "${args[@]}"
            ;;
        clear)
            cmd_clear "${args[@]}"
            ;;
        *)
            print_help
            exit 1
            ;;
    esac
}

main "$@"