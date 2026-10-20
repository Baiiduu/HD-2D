#!/bin/bash
set -euo pipefail
# Run on the database host. The application password is not placed in argv.
test "$(id -u)" = 0
install -d -m 700 /var/backups/hd2d-leaderboard
stamp=$(date -u +%Y%m%dT%H%M%SZ)
target=/var/backups/hd2d-leaderboard/$stamp
install -d -m 700 "$target"
runuser -u postgres -- /usr/lib/postgresql/18/bin/pg_dump --format=custom --no-owner leaderboard > "$target/leaderboard.dump"
install -m 600 /etc/hd2d-leaderboard/leaderboard.env "$target/leaderboard.env"
install -m 600 /etc/hd2d-leaderboard/server.key "$target/server.key"
install -m 644 /etc/hd2d-leaderboard/server.crt "$target/server.crt"
readlink -f /opt/hd2d-leaderboard/current > "$target/release.txt"
chmod 600 "$target/leaderboard.dump" "$target/release.txt"
echo "Backup complete: $target (contains private configuration; do not publish)."
