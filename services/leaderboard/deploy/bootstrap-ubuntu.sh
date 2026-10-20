#!/bin/bash
set -euo pipefail

# Install alongside the system Python and existing databases; no Docker.
test "$(id -u)" = 0
lb_suite=$(. /etc/os-release; printf '%s' "$VERSION_CODENAME")
lb_arch=$(dpkg --print-architecture)
base=/opt/hd2d-leaderboard
install -d "$base/releases" "$base/tools" /etc/hd2d-leaderboard /var/cache/hd2d-leaderboard
if ! id leaderboard >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/hd2d-leaderboard --shell /usr/sbin/nologin leaderboard
fi
if ! test -x "$base/tools/uv"; then
    curl -fsSL --connect-timeout 15 --max-time 120 https://astral.sh/uv/0.13.3/install.sh -o /var/cache/hd2d-leaderboard/uv-install.sh
    UV_INSTALL_DIR="$base/tools" UV_NO_MODIFY_PATH=1 sh /var/cache/hd2d-leaderboard/uv-install.sh
fi
export UV_PYTHON_INSTALL_DIR="$base/python"
export UV_CACHE_DIR=/var/cache/hd2d-leaderboard/uv
"$base/tools/uv" python install 3.13
"$base/tools/uv" python find 3.13 > "$base/python-path"

if ! test -x /usr/lib/postgresql/18/bin/psql; then
    install -d /usr/share/postgresql-common/pgdg /etc/postgresql-common/createcluster.d
    curl -fsSL --connect-timeout 15 --max-time 60 https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
    cat > /etc/apt/sources.list.d/hd2d-pgdg.sources <<EOF
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: ${lb_suite}-pgdg
Architectures: ${lb_arch}
Components: main
Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
EOF
    # Configure the new cluster before its first start.
    printf 'create_main_cluster = false\n' > /etc/postgresql-common/createcluster.d/hd2d.conf
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends postgresql-18 postgresql-client-18
fi
if ! test -d /etc/postgresql/18/main; then
    pg_createcluster --port=5432 --start-conf=auto \
        --pgoption="listen_addresses='127.0.0.1'" --pgoption='shared_buffers=64MB' \
        --pgoption='max_connections=20' --pgoption='work_mem=2MB' \
        --pgoption='maintenance_work_mem=32MB' --pgoption='jit=off' 18 main
fi
if ! pg_ctlcluster 18 main status >/dev/null 2>&1; then
    pg_ctlcluster 18 main start
fi
pg_isready -h 127.0.0.1 -p 5432
