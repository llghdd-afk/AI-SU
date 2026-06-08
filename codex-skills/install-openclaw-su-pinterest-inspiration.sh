#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install the su-pinterest-inspiration skill into OpenClaw/Qclaw.

Usage:
  ./codex-skills/install-openclaw-su-pinterest-inspiration.sh --global
  ./codex-skills/install-openclaw-su-pinterest-inspiration.sh --workspace "$HOME/.openclaw/workspace"
  ./codex-skills/install-openclaw-su-pinterest-inspiration.sh --dest "$HOME/.openclaw/skills"

Options:
  --global              Install to $HOME/.openclaw/skills
  --workspace PATH      Install to PATH/skills
  --dest PATH           Install directly to PATH
  --clean               Move any existing skill to a timestamped backup first
  --check               Run openclaw skills check/list after copying when openclaw is available
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="${script_dir}/su-pinterest-inspiration"
dest_root=""
clean=0
run_check=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      dest_root="${HOME}/.openclaw/skills"
      shift
      ;;
    --workspace)
      [[ $# -ge 2 ]] || { echo "--workspace requires a path" >&2; exit 2; }
      dest_root="$2/skills"
      shift 2
      ;;
    --dest)
      [[ $# -ge 2 ]] || { echo "--dest requires a path" >&2; exit 2; }
      dest_root="$2"
      shift 2
      ;;
    --clean)
      clean=1
      shift
      ;;
    --check)
      run_check=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$dest_root" ]]; then
  echo "Choose --global, --workspace PATH, or --dest PATH." >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$source_dir" ]]; then
  echo "Skill source not found: $source_dir" >&2
  exit 1
fi

mkdir -p "$dest_root"
target="${dest_root%/}/su-pinterest-inspiration"

if [[ "$clean" -eq 1 && -e "$target" ]]; then
  backup="${target}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$target" "$backup"
  echo "Backed up existing skill to $backup"
fi

rm -rf "$target.tmp"
cp -a "$source_dir" "$target.tmp"
rm -rf "$target"
mv "$target.tmp" "$target"

echo "Installed/updated skill at $target"
echo 'Invoke it with: use su-pinterest-inspiration / 使用 su-pinterest-inspiration'

if [[ "$run_check" -eq 1 ]] && command -v openclaw >/dev/null 2>&1; then
  openclaw skills info su-pinterest-inspiration || true
  openclaw skills check su-pinterest-inspiration || true
fi
