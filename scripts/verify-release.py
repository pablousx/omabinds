#!/usr/bin/env python3
"""Verify an omabinds release archive without trusting its contents."""
from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile


FILES = {
    'manifest.json', 'Panel.qml', 'BarWidget.qml', 'Model.js',
    'assets/keycap-3d.png', 'backend/omabinds.py', 'lua/runtime.lua',
    'scripts/install.py', 'scripts/install.sh', 'README.md', 'LICENSE',
}


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    release = Path(sys.argv[1] if len(sys.argv) > 1 else 'dist')
    manifest = json.loads(Path('manifest.json').read_text())
    version = manifest['version']
    root = f'omabinds-{version}'
    archive = release / f'{root}.tar.gz'
    sums = release / 'SHA256SUMS'
    license_asset = release / 'LICENSE'
    for path in (archive, sums, license_asset):
        if not path.is_file():
            fail(f'Missing release asset: {path}')
    if license_asset.read_bytes() != Path('LICENSE').read_bytes():
        fail('Release LICENSE differs from the repository license.')

    expected_sums = {}
    for line in sums.read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([^/]+)', line)
        if not match:
            fail(f'Invalid checksum line: {line!r}')
        expected_sums[match.group(2)] = match.group(1)
    if set(expected_sums) != {archive.name, 'LICENSE'}:
        fail('SHA256SUMS must contain exactly the archive and LICENSE.')
    for path in (archive, license_asset):
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if expected_sums[path.name] != actual:
            fail(f'Checksum mismatch: {path.name}')

    with tarfile.open(archive, 'r:gz') as package:
        members = package.getmembers()
        regular = {member.name for member in members if member.isfile()}
        expected = {f'{root}/{name}' for name in FILES}
        if regular != expected:
            fail(f'Unexpected package members: {sorted(regular ^ expected)}')
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isdir() or member.isfile()):
                fail(f'Unsafe package member: {member.name}')
            expected_mode = 0o755 if member.isdir() else 0o644
            if member.mode != expected_mode or member.uid != 0 or member.gid != 0:
                fail(f'Unexpected metadata: {member.name}')
        embedded = json.load(io.TextIOWrapper(package.extractfile(f'{root}/manifest.json')))
        if embedded != manifest or embedded['id'] != 'pablousx.omabinds':
            fail('Embedded manifest does not match the release candidate.')
        with tempfile.TemporaryDirectory(prefix='omabinds-release-') as tmp:
            package.extractall(tmp, filter='data')
            subprocess.run(['omarchy', 'plugin', 'validate', str(Path(tmp) / root)], check=True)
    print(f'PASS: {archive.name} contains exactly {len(FILES)} files and all release assets verify.')


if __name__ == '__main__':
    main()
