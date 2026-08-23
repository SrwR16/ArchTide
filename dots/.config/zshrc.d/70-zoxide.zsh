# 70-zoxide.zsh — Smart cd with frecency (38k★)
# https://github.com/ajeetdsouza/zoxide

# zoxide is a binary, install via package manager:
#   pacman -S zoxide    # Arch
#   brew install zoxide # macOS
#   apt install zoxide  # Debian/Ubuntu
#   cargo install zoxide --locked

if command -v zoxide >/dev/null 2>&1; then
  # Explicit --cmd z: define only z / zi. Plain `cd` stays literal stock
# semantics; fuzzy frecency jumps are deliberate via `z <fragment>`.
eval "$(zoxide init zsh --cmd z)"
  # Import from atuin: zoxide import atuin
else
  # Silently skip if not installed
  # To install: run your package manager command above
fi