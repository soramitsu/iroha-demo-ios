#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Compile every storyboard to a temporary storyboardc bundle; ibtool will error if
# any outlet or asset reference is invalid, mimicking the CI lint step.
find "$REPO_ROOT/Example-Point/Example-Point" -name "*.storyboard" -print0 | while IFS= read -r -d '' storyboard; do
  relative="${storyboard#$REPO_ROOT/}"
  echo "Validating ${relative}"
  output="$TMP_DIR/$(basename "${storyboard%.*}").storyboardc"
  ibtool --warnings --errors --notices --output-format human-readable-text --compile "$output" "$storyboard"
done
