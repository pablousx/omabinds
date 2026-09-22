#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(realpath "$0")")/.."

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' "Refusing to package a dirty working tree." >&2
  exit 1
fi

version="$(python3 -c 'import json; print(json.load(open("manifest.json"))["version"])')"
epoch="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
name="omabinds-${version}"
archive="dist/${name}.tar.gz"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

files=(
  manifest.json Panel.qml BarWidget.qml Model.js
  assets/keycap-3d.png backend/omabinds.py lua/runtime.lua
  scripts/install.py scripts/install.sh README.md LICENSE
)

mkdir -p "$stage/$name"
for file in "${files[@]}"; do
  mkdir -p "$stage/$name/$(dirname "$file")"
  cp "$file" "$stage/$name/$file"
done
find "$stage/$name" -type d -exec chmod 0755 {} +
find "$stage/$name" -type f -exec chmod 0644 {} +

mkdir -p dist
tar --sort=name --format=posix --pax-option=delete=atime,delete=ctime \
  --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
  -C "$stage" -cf - "$name" | gzip -n > "$archive"
cp LICENSE dist/LICENSE
(
  cd dist
  sha256sum "${name}.tar.gz" LICENSE > SHA256SUMS
)
printf '%s\n' "$archive" "dist/SHA256SUMS" "dist/LICENSE"
