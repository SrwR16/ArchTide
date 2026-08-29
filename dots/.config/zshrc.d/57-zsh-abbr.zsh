# 57-zsh-abbr.zsh — Fish-style abbreviations (800★)
# https://github.com/olets/zsh-abbr
# Type abbreviation + Space/Enter to expand. Ctrl+Space to skip expansion.
# Abbreviations sync to ~/.config/zsh/abbr.zsh for dotfile management.

# Load via plugin-load (defined in 05-plugin-manager.zsh)
# Plugin repo: olets/zsh-abbr

# Configuration (before plugin loads)
export ABBR_USER_ABBREVIATIONS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/abbr.zsh"

# Apply user abbreviations after plugin loads
if (( $+functions[abbr] )); then
  # ── Git ────────────────────────────────────────────────────────────────────
  abbr add gco 'git checkout'
  abbr add gcb 'git checkout -b'
  abbr add gcm 'git checkout main'
  abbr add gcd 'git checkout develop'
  abbr add gp 'git push'
  abbr add gpf 'git push --force-with-lease'
  abbr add gl 'git pull'
  abbr add glr 'git pull --rebase'
  abbr add gf 'git fetch'
  abbr add gfa 'git fetch --all --prune'
  abbr add gs 'git status'
  abbr add ga 'git add'
  abbr add gaa 'git add --all'
  abbr add gc 'git commit'
  abbr add gcm 'git commit -m'
  abbr add gca 'git commit --amend'
  abbr add gcan 'git commit --amend --no-edit'
  abbr add gd 'git diff'
  abbr add gds 'git diff --staged'
  abbr add gb 'git branch'
  abbr add gba 'git branch -a'
  abbr add gbd 'git branch -d'
  abbr add gbD 'git branch -D'
  abbr add glog 'git log --oneline --graph --decorate'
  abbr add lg 'lazygit'

  # ── Kubernetes ─────────────────────────────────────────────────────────────
  abbr add k 'kubectl'
  abbr add kg 'kubectl get'
  abbr add kgp 'kubectl get pods'
  abbr add kgs 'kubectl get svc'
  abbr add kgd 'kubectl get deploy'
  abbr add kgn 'kubectl get nodes'
  abbr add kd 'kubectl describe'
  abbr add kl 'kubectl logs'
  abbr add klf 'kubectl logs -f'
  abbr add kex 'kubectl exec -it'
  abbr add kctx 'kubectx'
  abbr add kns 'kubens'
  abbr add k9 'k9s'

  # ── Terraform ──────────────────────────────────────────────────────────────
  abbr add tf 'terraform'
  abbr add tfi 'terraform init'
  abbr add tfp 'terraform plan'
  abbr add tfa 'terraform apply'
  abbr add tfd 'terraform destroy'
  abbr add tfv 'terraform validate'
  abbr add tff 'terraform fmt'

  # ── Helm ───────────────────────────────────────────────────────────────────
  abbr add h 'helm'
  abbr add hi 'helm install'
  abbr add hu 'helm upgrade'
  abbr add hul 'helm upgrade --install'
  abbr add hd 'helm delete'
  abbr add hl 'helm list'
  abbr add ht 'helm template'

  # ── Docker ─────────────────────────────────────────────────────────────────
  abbr add d 'docker'
  abbr add dc 'docker-compose'
  abbr add dps 'docker ps'
  abbr add di 'docker images'
  abbr add dex 'docker exec -it'
  abbr add dlogs 'docker logs'
  abbr add dprune 'docker system prune -af'

  # ── Flux / ArgoCD / Kustomize ──────────────────────────────────────────────
  abbr add fl 'flux'
  abbr add ac 'argocd'
  abbr add kz 'kustomize'
  abbr add kzb 'kustomize build'

  # ── Editor / Config ────────────────────────────────────────────────────────
  abbr add v 'nvim'
  abbr add vz 'nvim ~/.zshrc'
  abbr add sz 'source ~/.zshrc'
  abbr add vk 'nvim ~/.config/kitty/kitty.conf'
  abbr add vh 'nvim ~/.config/hypr/hyprland/keybinds.lua'

  # ── Misc ───────────────────────────────────────────────────────────────────
  abbr add .. 'cd ..'
  abbr add ... 'cd ../..'
  abbr add .... 'cd ../../..'
fi