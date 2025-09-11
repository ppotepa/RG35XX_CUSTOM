#!/bin/bash
# Model Plugin API Contract
# Each model plugin should source this file and implement the following functions:
# - model_name: echo a human-readable model name
# - model_init: optional one-time setup for env variables; safe to call multiple times
# - model_build [args...]: perform build steps for the model
# - model_flash [args...]: flash artifacts to the target device
# - model_help: print model-specific help/usage

# Helpers for plugins
model_function_exists() {
  declare -F "$1" >/dev/null 2>&1
}

require_functions() {
  local missing=()
  for fn in "$@"; do
    model_function_exists "$fn" || missing+=("$fn")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "Model plugin missing required functions: ${missing[*]}" >&2
    return 1
  fi
}
