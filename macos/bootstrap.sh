#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
RESOURCES=$(cd "$(dirname "$0")" && pwd)
RUNTIME="$HOME/Library/Application Support/DDMM Connect/Runtime"
PYTHON="$RUNTIME/python/bin/python3"
if [ ! -x "$PYTHON" ]; then
  [ "$(uname -m)" = arm64 ] || { echo '{"ok":false,"error":"当前安装包仅支持 Apple Silicon Mac"}'; exit 1; }
  mkdir -p "$RUNTIME"
  ARCHIVE="$RUNTIME/python.tar.gz"
  /usr/bin/curl --fail --location --retry 2 --max-time 300 --silent --show-error 'https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only_stripped.tar.gz' -o "$ARCHIVE"
  EXPECTED=353d5f1b4fd2715e7053f12f068435d5bbad16b91e057006b5d01e0925709a7e
  ACTUAL=$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')
  [ "$ACTUAL" = "$EXPECTED" ] || { echo '{"ok":false,"error":"Python 运行时校验失败"}'; exit 1; }
  /usr/bin/tar -xzf "$ARCHIVE" -C "$RUNTIME"
fi
exec "$PYTHON" "$RESOURCES/setup.py" "$@"
