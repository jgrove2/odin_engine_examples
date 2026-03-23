#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/examples"

# Check odin is available
if ! command -v odin &> /dev/null; then
    echo "Error: 'odin' not found in PATH"
    exit 1
fi

# Collect example directories
examples=()
while IFS= read -r -d '' dir; do
    name="$(basename "$dir")"
    examples+=("$name")
done < <(find "$EXAMPLES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if [ ${#examples[@]} -eq 0 ]; then
    echo "No examples found in $EXAMPLES_DIR"
    exit 1
fi

# Display menu
echo "Available examples:"
echo ""
for i in "${!examples[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${examples[$i]}"
done
echo ""
read -rp "Select an example [1-${#examples[@]}]: " choice

# Validate selection
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#examples[@]}" ]; then
    echo "Error: invalid selection '$choice'"
    exit 1
fi

selected="${examples[$((choice - 1))]}"
echo ""
echo "Running: $selected"
echo ""

odin run "$EXAMPLES_DIR/$selected" -collection:engine="$SCRIPT_DIR/engine"
