#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(realpath "$0")")/.."
mkdir -p dist
tar --exclude=__pycache__ --exclude='*.pyc' -czf dist/omabinds-1.0.0.tar.gz \
  manifest.json Panel.qml BarWidget.qml Model.js backend lua scripts tests docs README.md LICENSE
printf '%s\n' "dist/omabinds-1.0.0.tar.gz"
