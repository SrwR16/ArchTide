# 70-zoxide.zsh — Smart cd with frecency (zoxide)
# https://github.com/ajeetdsouza/zoxide

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
  # Import from atuin: zoxide import atuin
fi