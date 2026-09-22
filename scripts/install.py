#!/usr/bin/env python3
"""Install only owned files. No package-manager, root or system-file writes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

SOURCE = Path(__file__).resolve().parents[1]
PLUGIN = 'pablousx.omabinds'
config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config')))
data = Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share')))
target = config/'omarchy/plugins'/PLUGIN
launcher = data/'applications/omabinds.desktop'
FILES = ['manifest.json','Panel.qml','BarWidget.qml','Model.js','assets','backend','lua','scripts','README.md','LICENSE']


def command(args):
    proc = None
    for attempt in range(3):
        proc = subprocess.run(
            args, capture_output=True, text=True,
            env=dict(os.environ, OMARCHY_SHELL_IPC_TIMEOUT='15s'))
        if proc.returncode == 0:
            if proc.stdout: print(proc.stdout, end='')
            return
        if attempt < 2: time.sleep(2)
    if proc.stderr: print(proc.stderr, end='', file=sys.stderr)
    proc.check_returncode()


def shell_plugins():
    for attempt in range(3):
        proc = subprocess.run(
            ['omarchy-shell', 'shell', 'listPlugins'],
            capture_output=True, text=True,
            env=dict(os.environ, OMARCHY_SHELL_IPC_TIMEOUT='15s'))
        if proc.returncode == 0: return json.loads(proc.stdout)
        if attempt < 2: time.sleep(2)
    if proc.stderr: print(proc.stderr, end='', file=sys.stderr)
    proc.check_returncode()


def backend(op):
    proc = subprocess.run(['python3', str(target/'backend/omabinds.py'), op],capture_output=True,text=True)
    result=json.loads(proc.stdout)
    if not result['ok']:raise RuntimeError(result['error'])
    print(result.get('message','OK'))


if '--uninstall' in sys.argv:
    if target.exists():
        backend('uninstall')
        command(['omarchy-shell','shell','setPluginEnabled',PLUGIN,'false'])
        if launcher.exists() and 'X-omabinds-Owned=true' in launcher.read_text():launcher.unlink()
        # Preserve imported mappings and backups unless the user explicitly purges.
        if '--purge' in sys.argv:
            import argparse
            if '--yes' not in sys.argv:raise RuntimeError('Use --purge --yes to permanently delete the data.')
            shutil.rmtree(config/'omabinds',ignore_errors=True)
        shutil.rmtree(target)
        command(['omarchy-shell','shell','rescanPlugins'])
    print('omabinds uninstalled. All other user files were preserved.')
else:
    for binary in ['Hyprland','hyprctl','quickshell','omarchy-shell','gio','python3']:
        if not shutil.which(binary):raise RuntimeError('Missing dependency: '+binary)
    if launcher.exists() and 'X-omabinds-Owned=true' not in launcher.read_text():raise RuntimeError('The existing launcher does not belong to omabinds.')
    if target.exists() and target.resolve()!=SOURCE.resolve():
        manifest=json.loads((target/'manifest.json').read_text())
        if manifest.get('id')!=PLUGIN:raise RuntimeError('The destination directory belongs to another plugin.')
    target.mkdir(parents=True,exist_ok=True)
    if target.resolve()!=SOURCE.resolve():
        for name in FILES:
            src=SOURCE/name;dst=target/name
            if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
            else:shutil.copy2(src,dst)
    backend('install')
    launcher.parent.mkdir(parents=True,exist_ok=True)
    launcher.write_text('[Desktop Entry]\nType=Application\nName=omabinds\nComment=Keyboard shortcuts, applications, and actions\nExec=omarchy-shell shell summon pablousx.omabinds {}\nIcon=' + str(target/'assets/keycap-3d.png') + '\nTerminal=false\nCategories=Settings;Utility;\nX-omabinds-Owned=true\n')
    command(['omarchy-shell','shell','rescanPlugins'])
    command(['omarchy-shell','shell','setPluginEnabled',PLUGIN,'true'])
    # Pre-4.0 manifests could leave a now-bar-widget plugin in the generic
    # `plugins` list. setPluginEnabled then reports success but cannot create a
    # live bar slot. Migrate only that stale state; an existing bar placement
    # remains untouched on normal reinstalls.
    installed = next((p for p in shell_plugins() if p.get('id') == PLUGIN), None)
    if installed and not installed.get('enabled'):
        command(['omarchy-shell','shell','setPluginEnabled',PLUGIN,'false'])
        command(['omarchy-shell','shell','enablePlugin',PLUGIN,'{}'])
    print('Installed. Open omabinds from the launcher or its bar icon.')
