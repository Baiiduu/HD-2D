#!/bin/bash
set -euo pipefail
test "$(id -u)" = 0
archive=$(realpath "${1:?Pass the release tar.gz path}")
base=/opt/hd2d-leaderboard
release=$(tar -xOf "$archive" release.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["release"])')
[[ "$release" =~ ^[0-9a-f]{16}$ ]] || exit 1
target="$base/releases/$release"
if ! test -d "$target"; then
    install -d "$target"
    tar -xzf "$archive" -C "$target" --no-same-owner
fi
export UV_CACHE_DIR=/var/cache/hd2d-leaderboard/uv
export UV_PYTHON_INSTALL_DIR="$base/python"
if ! test -x "$target/.venv/bin/python"; then
    "$base/tools/uv" venv --python "$(cat "$base/python-path")" "$target/.venv"
fi
"$base/tools/uv" pip sync --python "$target/.venv/bin/python" "$target/requirements-linux.lock"
chmod -R a+rX "$base/python" "$target"
"$target/.venv/bin/python" "$target/deploy/initialize.py"
if ! test -e "$base/current" && ! test -L "$base/current"; then
    ln -s "$target" "$base/current"
fi
echo "Release staged: $target"
echo 'Existing current symlink and running service are preserved during staging.'
