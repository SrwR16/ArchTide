#!/bin/bash
# Flow dependency registry — tiers, resolution, installation.
# Sources platform.sh for pkg_install.

declare -gA FLOW_DEPS_META=()
declare -ga FLOW_DEPS_KEYS=()

flow_dep() {
    local key="$1" tier="$2" pkg="$3" reason="$4" bin="${5:-$key}"
    FLOW_DEPS_META["$key"]="$tier|$pkg|$reason|$bin"
    FLOW_DEPS_KEYS+=("$key")
}

deps_init() {
    # Core — always installed
    flow_dep zsh        core zsh        "Shell runtime"            zsh
    flow_dep git        core git        "Version control"           git
    flow_dep starship   core starship   "Prompt"                    starship
    flow_dep atuin      core atuin      "History search (^R)"       atuin
    flow_dep mise       core mise       "Runtime version manager"   mise
    flow_dep fzf        core fzf        "Fuzzy finder"              fzf
    flow_dep fd         core fd         "Fast find (fzf default)"   fd
    flow_dep ripgrep    core rg         "Fast grep"                 rg
    flow_dep zoxide     core zoxide     "Smart cd (z/zi)"           zoxide
    flow_dep direnv     core direnv     "Per-project env"           direnv
    # UX
    flow_dep bat        ux bat          "Syntax-highlighting cat"   bat
    flow_dep eza        ux eza          "Modern ls"                 eza
    flow_dep lazygit    ux lazygit      "Terminal git UI"           lazygit
    # DevOps
    flow_dep docker     devops docker       "Containers"              docker
    flow_dep kubectl    devops kubectl      "Kubernetes CLI"           kubectl
    flow_dep helm       devops helm         "K8s package manager"      helm
    flow_dep kind       devops kind         "Local K8s clusters"       kind
    flow_dep terraform  devops terraform   "IaC (Terraform)"           terraform
    flow_dep opentofu   devops opentofu     "OpenTofu (Terraform alt)" tofu
    flow_dep ansible    devops ansible      "Config management"         ansible
    flow_dep gh         devops github-cli   "GitHub CLI"                gh
    flow_dep aws-cli    devops aws-cli      "AWS CLI"                   aws
    flow_dep k9s        devops k9s          "K8s TUI"                   k9s
    flow_dep stern      devops stern        "Multi-pod log tailing"     stern
    flow_dep kubectx    devops kubectx      "Kube context switcher"     kubectx
    flow_dep trivy      devops trivy        "Container/IaC scanner"     trivy
    flow_dep cosign     devops cosign       "Container signing"         cosign
    flow_dep vault      devops vault        "HashiCorp Vault CLI"       vault
    flow_dep sops       devops sops         "Secrets encryption"         sops
    flow_dep age        devops age          "Modern encryption"          age
    flow_dep dive       devops dive         "Docker image inspector"    dive
    flow_dep pre-commit devops pre-commit   "Git hook framework"         pre-commit
    flow_dep tmux       devops tmux         "Terminal multiplexer"       tmux
    flow_dep argocd     devops argocd       "GitOps CD CLI"              argocd
    flow_dep eksctl     devops eksctl       "EKS cluster CLI"            eksctl
    flow_dep kustomize  devops kustomize    "K8s templating"             kustomize
    flow_dep docker-compose devops docker-compose "Compose v2"         docker-compose
    flow_dep yq         devops go-yq        "YAML processor (mikefarah)" yq
}

deps_missing() {
    local tier="$1"
    local -a missing=()
    for key in "${FLOW_DEPS_KEYS[@]}"; do
        local meta="${FLOW_DEPS_META[$key]}"
        IFS='|' read -r k t pkg reason bin <<<"$meta"
        [[ "$t" == "$tier" ]] || continue
        command -v "$bin" &>/dev/null || missing+=("$key")
    done
    printf '%s\n' "${missing[@]+"${missing[@]}"}"
}

deps_tier_keys() {
    local tier="$1"
    for key in "${FLOW_DEPS_KEYS[@]}"; do
        local meta="${FLOW_DEPS_META[$key]}"
        IFS='|' read -r k t pkg reason bin <<<"$meta"
        [[ "$t" == "$tier" ]] && echo "$key"
    done
}
