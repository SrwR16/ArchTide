#!/usr/bin/env bash
#
# flow project detect — read-only project intelligence
# Part of Flow Terminal Phase 2
#

set -Eeuo pipefail

# Colors for human output
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

# JSON output flag
JSON_OUTPUT=false
for arg in "$@"; do
    case "$arg" in
        --json) JSON_OUTPUT=true ;;
    esac
done

# Utility functions
print_human() { [[ "$JSON_OUTPUT" == false ]] && printf '%b\n' "$*"; }

# Escape JSON string
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Detect Git repository root
get_git_root() {
    git rev-parse --show-toplevel 2>/dev/null || return 1
}

# Find project root by walking up from PWD
find_project_root() {
    local dir="$PWD"
    local markers=(
        "pyproject.toml" "package.json" "go.mod" "Cargo.toml"
        "composer.json" "Gemfile" "pom.xml" "build.gradle" "build.gradle.kts"
        "mix.exs" "CMakeLists.txt" "Makefile" "Taskfile.yml" "Justfile"
        "Dockerfile" "Containerfile" "compose.yaml" "compose.yml"
        "docker-compose.yml" "docker-compose.yaml" "Chart.yaml"
        "kustomization.yaml" "ansible.cfg"
        ".github" "terraform"
    )

    while [[ "$dir" != "/" ]]; do
        for marker in "${markers[@]}"; do
            if [[ -e "$dir/$marker" ]]; then
                printf '%s\n' "$dir"
                return 0
            fi
        done
        dir="$(dirname "$dir")"
    done
    return 1
}

# Get project name
get_project_name() {
    local root="$1"
    local git_root="$2"

    if [[ -n "$git_root" && "$git_root" == "$root" ]]; then
        basename "$git_root"
        return
    fi

    # Check for explicit project metadata
    if [[ -f "$root/pyproject.toml" ]]; then
        grep -E '^name\s*=' "$root/pyproject.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"?([^"]+)"?/\1/' | xargs
        return
    fi
    if [[ -f "$root/package.json" ]]; then
        grep -E '"name"\s*:' "$root/package.json" 2>/dev/null | head -1 | sed -E 's/.*:\s*"([^"]+)".*/\1/' | xargs
        return
    fi
    if [[ -f "$root/Cargo.toml" ]]; then
        grep -E '^name\s*=' "$root/Cargo.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' | xargs
        return
    fi

    basename "$root"
}

# Detect capabilities in project root
detect_capabilities() {
    local root="$1"

    # Output arrays (using global variables for simplicity)
    LANGUAGES=()
    FRAMEWORKS=()
    PACKAGE_MANAGERS=()
    RUNTIMES=()
    CONTAINERS=()
    INFRASTRUCTURE=()
    KUBERNETES=()
    CI_CD=()
    TASK_RUNNERS=()
    EVIDENCE=()
    ENV_CANDIDATES=()
    RUNTIME_HINTS=()

    # Helper: add evidence
    add_evidence() {
        EVIDENCE+=("$1")
    }

    # Helper: add capability with confidence
    add_cap() {
        local arr_name="$1"
        local name="$2"
        local confidence="$3"
        local evidence="$4"
        # Use printf to build the element safely
        local element="${name}|${confidence}|${evidence}"
        eval "${arr_name}+=(\"\${element}\")"
    }

    # === Python ===
    local python_detected=false
    local python_frameworks=()
    local python_envs=()
    local uv_lock=false

    if [[ -f "$root/manage.py" ]]; then
        python_detected=true
        python_frameworks+=("django|high|manage.py")
        add_evidence "manage.py"
    fi
    if [[ -f "$root/pyproject.toml" ]]; then
        python_detected=true
        add_evidence "pyproject.toml"
        if grep -q 'django' "$root/pyproject.toml" 2>/dev/null; then
            python_frameworks+=("django|medium|pyproject.toml dependency")
        fi
        if grep -q 'fastapi' "$root/pyproject.toml" 2>/dev/null; then
            python_frameworks+=("fastapi|medium|pyproject.toml dependency")
        fi
        if grep -q 'flask' "$root/pyproject.toml" 2>/dev/null; then
            python_frameworks+=("flask|medium|pyproject.toml dependency")
        fi
        if grep -q 'poetry' "$root/pyproject.toml" 2>/dev/null; then
            add_cap PACKAGE_MANAGERS "poetry" "medium" "pyproject.toml"
        fi
    fi
    if [[ -f "$root/uv.lock" ]]; then
        python_detected=true
        uv_lock=true
        add_evidence "uv.lock"
        add_cap PACKAGE_MANAGERS "uv" "high" "uv.lock"
    fi
    if [[ -f "$root/requirements.txt" ]] || [[ -d "$root/requirements" ]]; then
        python_detected=true
        add_evidence "requirements.txt"
        add_cap PACKAGE_MANAGERS "pip" "medium" "requirements.txt"
    fi
    if [[ -f "$root/Pipfile" ]]; then
        python_detected=true
        add_evidence "Pipfile"
        add_cap PACKAGE_MANAGERS "pipenv" "high" "Pipfile"
    fi
    if [[ -f "$root/poetry.lock" ]]; then
        python_detected=true
        add_evidence "poetry.lock"
        add_cap PACKAGE_MANAGERS "poetry" "high" "poetry.lock"
    fi
    if [[ -f "$root/setup.py" ]] || [[ -f "$root/setup.cfg" ]]; then
        python_detected=true
        add_evidence "setup.py/setup.cfg"
    fi
    if [[ -f "$root/.python-version" ]]; then
        add_evidence ".python-version"
        RUNTIME_HINTS+=("python_version_file|.python-version")
    fi

    # Python environments
    for env in ".venv" "venv" "env"; do
        if [[ -d "$root/$env" ]]; then
            python_envs+=("$env|venv|true")
        fi
    done

    if [[ "$python_detected" == true ]]; then
        add_cap LANGUAGES "python" "high" "multiple indicators"
        for fw in "${python_frameworks[@]}"; do
            IFS='|' read -r fw_name fw_conf fw_ev <<< "$fw"
            add_cap FRAMEWORKS "$fw_name" "$fw_conf" "$fw_ev"
        done
        ENV_CANDIDATES+=("python|$(IFS=,; echo "${python_envs[*]}")|uv_lock:$uv_lock")
    fi

    # === Node/JavaScript ===
    local node_detected=false
    if [[ -f "$root/package.json" ]]; then
        node_detected=true
        add_evidence "package.json"
        add_cap LANGUAGES "javascript" "high" "package.json"
        add_cap LANGUAGES "typescript" "medium" "package.json (likely)"

        if [[ -f "$root/pnpm-lock.yaml" ]]; then
            add_cap PACKAGE_MANAGERS "pnpm" "high" "pnpm-lock.yaml"
            add_evidence "pnpm-lock.yaml"
        elif [[ -f "$root/yarn.lock" ]]; then
            add_cap PACKAGE_MANAGERS "yarn" "high" "yarn.lock"
            add_evidence "yarn.lock"
        elif [[ -f "$root/bun.lock" ]] || [[ -f "$root/bun.lockb" ]]; then
            add_cap PACKAGE_MANAGERS "bun" "high" "bun.lock"
            add_evidence "bun.lock"
        else
            add_cap PACKAGE_MANAGERS "npm" "medium" "package.json (default)"
        fi

        if [[ -f "$root/.nvmrc" ]]; then
            add_evidence ".nvmrc"
            RUNTIME_HINTS+=("node_version_file|.nvmrc")
        fi
        if [[ -f "$root/.node-version" ]]; then
            add_evidence ".node-version"
            RUNTIME_HINTS+=("node_version_file|.node-version")
        fi
    fi

    # === Go ===
    if [[ -f "$root/go.mod" ]]; then
        add_cap LANGUAGES "go" "high" "go.mod"
        add_evidence "go.mod"
        if [[ -f "$root/go.sum" ]]; then
            add_evidence "go.sum"
        fi
    fi

    # === Rust ===
    if [[ -f "$root/Cargo.toml" ]]; then
        add_cap LANGUAGES "rust" "high" "Cargo.toml"
        add_evidence "Cargo.toml"
        if [[ -f "$root/Cargo.lock" ]]; then
            add_evidence "Cargo.lock"
        fi
    fi

    # === Java/JVM ===
    if [[ -f "$root/pom.xml" ]]; then
        add_cap LANGUAGES "java" "high" "pom.xml"
        add_cap PACKAGE_MANAGERS "maven" "high" "pom.xml"
        add_evidence "pom.xml"
    fi
    if [[ -f "$root/build.gradle" ]] || [[ -f "$root/build.gradle.kts" ]]; then
        add_cap LANGUAGES "java" "high" "build.gradle"
        add_cap PACKAGE_MANAGERS "gradle" "high" "build.gradle"
        add_evidence "build.gradle"
    fi

    # === PHP ===
    if [[ -f "$root/composer.json" ]]; then
        add_cap LANGUAGES "php" "high" "composer.json"
        add_cap PACKAGE_MANAGERS "composer" "high" "composer.json"
        add_evidence "composer.json"
        if [[ -f "$root/composer.lock" ]]; then
            add_evidence "composer.lock"
        fi
    fi

    # === Ruby ===
    if [[ -f "$root/Gemfile" ]]; then
        add_cap LANGUAGES "ruby" "high" "Gemfile"
        add_cap PACKAGE_MANAGERS "bundler" "high" "Gemfile"
        add_evidence "Gemfile"
        if [[ -f "$root/Gemfile.lock" ]]; then
            add_evidence "Gemfile.lock"
        fi
    fi

    # === Docker/Containers ===
    if [[ -f "$root/Dockerfile" ]] || [[ -f "$root/Containerfile" ]]; then
        add_cap CONTAINERS "docker" "high" "Dockerfile"
        add_evidence "Dockerfile"
    fi
    if [[ -f "$root/compose.yaml" ]] || [[ -f "$root/compose.yml" ]] \
       || [[ -f "$root/docker-compose.yml" ]] || [[ -f "$root/docker-compose.yaml" ]]; then
        add_cap CONTAINERS "compose" "high" "compose file"
        add_evidence "compose file"
    fi

    # === Terraform/OpenTofu ===
    if compgen -G "$root/*.tf" >/dev/null 2>&1 || compgen -G "$root/*.tf.json" >/dev/null 2>&1; then
        add_cap INFRASTRUCTURE "terraform" "high" "*.tf files"
        add_evidence "terraform files"
    fi
    if [[ -d "$root/.terraform" ]]; then
        add_evidence ".terraform directory"
    fi
    if compgen -G "$root/*.tfvars" >/dev/null 2>&1 || [[ -f "$root/terraform.tfvars" ]]; then
        add_evidence "tfvars files"
    fi

    # === Kubernetes/Helm ===
    for k8s_dir in "k8s" "kubernetes" "manifests"; do
        if [[ -d "$root/$k8s_dir" ]]; then
            add_cap KUBERNETES "kubernetes" "medium" "$k8s_dir/ directory"
            add_evidence "$k8s_dir/ directory"
            break
        fi
    done
    if [[ -f "$root/kustomization.yaml" ]]; then
        add_cap KUBERNETES "kustomize" "high" "kustomization.yaml"
        add_evidence "kustomization.yaml"
    fi
    if [[ -f "$root/Chart.yaml" ]]; then
        add_cap KUBERNETES "helm" "high" "Chart.yaml"
        add_cap CONTAINERS "helm" "medium" "Chart.yaml"
        add_evidence "Chart.yaml"
    fi
    if [[ -d "$root/helm" ]] || [[ -d "$root/charts" ]]; then
        add_cap KUBERNETES "helm" "medium" "helm/ or charts/ directory"
        add_evidence "helm/ or charts/ directory"
    fi

    # Quick YAML check for Kubernetes resources (only small files in known dirs)
    for k8s_dir in "k8s" "kubernetes" "manifests"; do
        if [[ -d "$root/$k8s_dir" ]]; then
            while IFS= read -r -d '' file; do
                [[ ${#file} -gt 10000 ]] && continue
                if head -20 "$file" 2>/dev/null | grep -qE '^apiVersion:|^kind:|^metadata:'; then
                    add_cap KUBERNETES "kubernetes" "low" "YAML with k8s markers in $k8s_dir/"
                    break
                fi
            done < <(find "$root/$k8s_dir" -maxdepth 2 -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null)
            break
        fi
    done

    # === CI/CD ===
    if [[ -d "$root/.github/workflows" ]]; then
        add_cap CI_CD "github-actions" "high" ".github/workflows/"
        add_evidence ".github/workflows/"
    fi
    if [[ -f "$root/.gitlab-ci.yml" ]]; then
        add_cap CI_CD "gitlab-ci" "high" ".gitlab-ci.yml"
        add_evidence ".gitlab-ci.yml"
    fi
    if [[ -f "$root/Jenkinsfile" ]]; then
        add_cap CI_CD "jenkins" "high" "Jenkinsfile"
        add_evidence "Jenkinsfile"
    fi

    # === Task Runners ===
    if [[ -f "$root/Makefile" ]]; then
        add_cap TASK_RUNNERS "make" "high" "Makefile"
        add_evidence "Makefile"
    fi
    if [[ -f "$root/Taskfile.yml" ]] || [[ -f "$root/Taskfile.yaml" ]]; then
        add_cap TASK_RUNNERS "task" "high" "Taskfile"
        add_evidence "Taskfile"
    fi
    if [[ -f "$root/Justfile" ]]; then
        add_cap TASK_RUNNERS "just" "high" "Justfile"
        add_evidence "Justfile"
    fi

    # === Mise ===
    if [[ -f "$root/mise.toml" ]]; then
        RUNTIME_HINTS+=("mise_toml|true")
        add_evidence "mise.toml"
    fi
    if [[ -f "$root/.mise.toml" ]]; then
        RUNTIME_HINTS+=("mise_toml_local|true")
        add_evidence ".mise.toml"
    fi
    if [[ -f "$root/.tool-versions" ]]; then
        RUNTIME_HINTS+=("asdf_tool_versions|true")
        add_evidence ".tool-versions"
    fi
}

# Main detection function
main() {
    local git_root=""
    local project_root=""
    local project_name=""
    local repo_type="none"

    # Try Git root first
    if git_root=$(get_git_root); then
        project_root="$git_root"
        repo_type="git"
    else
        # Fall back to marker-based detection
        if project_root=$(find_project_root); then
            repo_type="markers"
        else
            project_root="$PWD"
            repo_type="none"
        fi
    fi

    project_name=$(get_project_name "$project_root" "$git_root")

    # Detect capabilities
    detect_capabilities "$project_root"

    # Output
    if [[ "$JSON_OUTPUT" == true ]]; then
        # Build JSON output
        printf '{\n'
        printf '  "schema_version": 1,\n'
        printf '  "root": "%s",\n' "$(json_escape "$project_root")"
        printf '  "name": "%s",\n' "$(json_escape "$project_name")"
        printf '  "repository": {\n'
        printf '    "type": "%s",\n' "$(json_escape "$repo_type")"
        printf '    "root": "%s"\n' "$(json_escape "${git_root:-$project_root}")"
        printf '  },\n'

        # Helper to output array
        output_json_array() {
            local name="$1"
            local -n arr=$1
            printf '  "%s": [' "$name"
            local first=true
            for item in "${arr[@]}"; do
                [[ "$first" == true ]] && first=false || printf ', '
                printf '"%s"' "$(json_escape "$item")"
            done
            printf '],\n'
        }

        output_json_array "LANGUAGES"
        output_json_array "FRAMEWORKS"
        output_json_array "PACKAGE_MANAGERS"
        output_json_array "RUNTIMES"
        output_json_array "CONTAINERS"
        output_json_array "INFRASTRUCTURE"
        output_json_array "KUBERNETES"
        output_json_array "CI_CD"
        output_json_array "TASK_RUNNERS"
        output_json_array "EVIDENCE"
        output_json_array "ENV_CANDIDATES"
        output_json_array "RUNTIME_HINTS"

        printf '  "note": "No environment was activated. No project files were modified."\n'
        printf '}\n'
    else
        # Human output
        print_human "${C_BOLD}${C_CYAN}Flow Project Context${C_RESET}"
        print_human "${C_DIM}────────────────────────────────────────${C_RESET}"
        print_human ""
        print_human "Root"
        print_human "  ${C_BOLD}$project_root${C_RESET}"
        print_human ""
        print_human "Project"
        print_human "  $project_name"
        print_human ""
        print_human "Repository"
        case "$repo_type" in
            git) print_human "  ${C_GREEN}Git${C_RESET}" ;;
            markers) print_human "  ${C_YELLOW}Markers only${C_RESET}" ;;
            *) print_human "  ${C_DIM}None detected${C_RESET}" ;;
        esac
        print_human ""

        # Languages
        if [[ ${#LANGUAGES[@]} -gt 0 ]]; then
            print_human "Languages"
            for lang in "${LANGUAGES[@]}"; do
                local name="${lang%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # Frameworks
        if [[ ${#FRAMEWORKS[@]} -gt 0 ]]; then
            print_human "Frameworks"
            for fw in "${FRAMEWORKS[@]}"; do
                local name="${fw%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # Package managers
        if [[ ${#PACKAGE_MANAGERS[@]} -gt 0 ]]; then
            print_human "Package managers"
            for pm in "${PACKAGE_MANAGERS[@]}"; do
                local name="${pm%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # Python details
        for env in "${ENV_CANDIDATES[@]}"; do
            if [[ "$env" == python* ]]; then
                print_human "Python"
                local details="${env#python|}"
                IFS='|' read -r envs uv_lock <<< "$details"
                if [[ -n "$envs" && "$envs" != "" ]]; then
                    for e in ${envs//,/ }; do
                        print_human "  ${C_GREEN}●${C_RESET} $e"
                    done
                fi
                if [[ "$uv_lock" == *"true"* ]]; then
                    print_human "  ${C_CYAN}uv.lock${C_RESET} present"
                fi
                print_human ""
                break
            fi
        done

        # Containers
        if [[ ${#CONTAINERS[@]} -gt 0 ]]; then
            print_human "Containers"
            for c in "${CONTAINERS[@]}"; do
                local name="${c%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # Infrastructure
        if [[ ${#INFRASTRUCTURE[@]} -gt 0 ]]; then
            print_human "Infrastructure"
            for i in "${INFRASTRUCTURE[@]}"; do
                local name="${i%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # Kubernetes
        if [[ ${#KUBERNETES[@]} -gt 0 ]]; then
            print_human "Kubernetes"
            for k in "${KUBERNETES[@]}"; do
                local name="${k%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # CI/CD
        if [[ ${#CI_CD[@]} -gt 0 ]]; then
            print_human "CI/CD"
            for c in "${CI_CD[@]}"; do
                local name="${c%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        # Task runners
        if [[ ${#TASK_RUNNERS[@]} -gt 0 ]]; then
            print_human "Task runners"
            for t in "${TASK_RUNNERS[@]}"; do
                local name="${t%%|*}"
                print_human "  $name"
            done
            print_human ""
        fi

        if [[ ${#LANGUAGES[@]} -eq 0 && ${#FRAMEWORKS[@]} -eq 0 && ${#CONTAINERS[@]} -eq 0 && ${#INFRASTRUCTURE[@]} -eq 0 && ${#KUBERNETES[@]} -eq 0 && ${#CI_CD[@]} -eq 0 && ${#TASK_RUNNERS[@]} -eq 0 ]]; then
            print_human "${C_YELLOW}No recognized project markers.${C_RESET}"
            print_human ""
        fi

        print_human "${C_DIM}No environment was activated.${C_RESET}"
        print_human "${C_DIM}No project files were modified.${C_RESET}"
    fi
}

main "$@"