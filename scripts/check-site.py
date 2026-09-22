#!/usr/bin/env python3
"""Validate the static Pages boundary, local links and release metadata."""
from __future__ import annotations

from html.parser import HTMLParser
import json
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'docs'
PAGES = ('index.html', 'privacy.html', 'terms.html')


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get('id'):
            self.ids.add(values['id'])
        for key in ('href', 'src'):
            if values.get(key):
                self.links.append(values[key])


parsed = {}
for name in PAGES:
    page = Page()
    page.feed((SITE / name).read_text())
    parsed[name] = page

for name, page in parsed.items():
    for link in page.links:
        target = urlsplit(link)
        if target.scheme or target.netloc or link.startswith(('mailto:', 'data:')):
            continue
        path = target.path or name
        destination = (SITE / path).resolve()
        if SITE.resolve() not in destination.parents and destination != SITE.resolve():
            raise SystemExit(f'{name}: link escapes docs/: {link}')
        if not destination.exists():
            raise SystemExit(f'{name}: missing local target: {link}')
        if target.fragment:
            target_name = path if path.endswith('.html') else name
            if target_name in parsed and target.fragment not in parsed[target_name].ids:
                raise SystemExit(f'{name}: missing anchor: {link}')

version = json.loads((ROOT / 'manifest.json').read_text())['version']
index = (SITE / 'index.html').read_text()
if f'v{version}' not in index:
    raise SystemExit('Website version does not match manifest.json.')
for asset in (f'omabinds-{version}.tar.gz', 'SHA256SUMS', 'LICENSE'):
    if f'/releases/download/v{version}/{asset}' not in index:
        raise SystemExit(f'Missing release download link: {asset}')
if (ROOT / 'preview.png').read_bytes() != (SITE / 'preview.png').read_bytes():
    raise SystemExit('Root and website previews differ.')
for copy in (SITE / 'LICENSE.txt', SITE / 'assets/LICENSE.txt'):
    if copy.read_bytes() != (ROOT / 'LICENSE').read_bytes():
        raise SystemExit(f'License copy differs: {copy.relative_to(ROOT)}')
print('PASS: website pages, local targets, release links, preview and license copies are consistent.')
