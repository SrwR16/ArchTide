# 90-iris.zsh — IRIS Intelligent Real-time Input Suggestion
# Replaces custom Flow ZLE predictor/HUD with official IRIS presentation engine.
# https://github.com/versenilvis/iris
#
# Provides: Inline ghost text, candidate HUD, candidate navigation (Up/Down/Tab/Right),
# history completion, alias expansion, and native Atuin history integration.

if command -v iris >/dev/null 2>&1; then
  eval "$(iris init zsh)"
fi
