#!/bin/bash
set -euo pipefail

mode="${1:-offline}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$mode" in
  offline)
    exec python3 "$script_dir/framework/runner.py"
    ;;
  *)
    echo "Unsupported test mode: $mode" >&2
    echo "Usage: $0 offline" >&2
    exit 2
    ;;
esac

