"""Explicit opt-in live acceptance test; always restores the managed state.

Run with --apply in an unlocked graphical session. F20/F21/F22 must be free.
Executes registered callables through Hyprland's Lua API, without key synthesis.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backend.omabinds import Controller, Error, apps, revision, run

if '--apply' not in sys.argv:raise SystemExit('Requires --apply: installs temporary F20/F21/F22 mappings and restores state.')
c=Controller()
report=[]

def mark(text):
    report.append(text); print(text,flush=True)

def semantic(bindings):
    return sorted(json.dumps({k:v for k,v in b.items() if k!='arg'},sort_keys=True) for b in bindings)

with c.lock():
    saved=copy.deepcopy(c.state())
    before=semantic(c.live())
    source=next(b for b in c.catalog()['bindings'] if b['id']=='|SUPER + V')
    obsidian=next((a for a in apps() if 'obsidian' in a['name'].lower()), None)
    with tempfile.TemporaryDirectory(prefix='omabinds-live-') as tmp:
        marker=Path(tmp)/'command-executed'
        app_marker=Path(tmp)/'application-executed'
        old_data=os.environ.get('XDG_DATA_HOME')
        if not obsidian:
            appdir=Path(tmp)/'applications';appdir.mkdir()
            (appdir/'omabinds-test.desktop').write_text('[Desktop Entry]\nType=Application\nName=omabinds acceptance\nIcon=input-keyboard\nExec=/usr/bin/touch '+str(app_marker)+'\n')
            os.environ['XDG_DATA_HOME']=tmp
            application=next(a for a in apps() if a['id']=='omabinds-test.desktop')
        else: application=obsidian
        mappings=[
            {'id':'acceptance_f20','name':'Test application','trigger':'F20','enabled':True,'action':{'kind':'app','desktop':application['id']}},
            {'id':'acceptance_f21','name':'Test command','trigger':'F21','enabled':True,'action':{'kind':'command','command':'touch '+str(marker)}},
            {'id':'acceptance_f22','name':'Test clipboard alias','trigger':'F22','enabled':True,'action':{'kind':'alias','source':source['id'],'signature':source['signature']}}
        ]
        candidate=copy.deepcopy(saved);candidate['mappings']+=mappings
        try:
            result=c.commit({'state':candidate,'revision':revision(c.state())})
            if result.get('conflicts'):raise Error(json.dumps(result['conflicts']))
            mark('PASS: F20 app, F21 command, F22 alias committed and verified by live compositor')
            live=c.live()
            assert any(b['modmask']==64 and b['key'].upper()=='V' and b['description']==source['name'] for b in live)
            mark('PASS: original SUPER+V remains effective')
            run(['hyprctl','eval', 'hl.dispatch(omabinds_runtime.applied["acceptance_f21"][1].action)'])
            for _ in range(40):
                if marker.exists():break
                time.sleep(.05)
            assert marker.exists(),'F21 action did not execute the command'
            mark('PASS: F21 registered callable executed the custom command')
            run(['hyprctl','eval', 'hl.dispatch(omabinds_runtime.applied["acceptance_f20"][1].action)'])
            for _ in range(60):
                clients=json.loads(run(['hyprctl','-j','clients']))
                if app_marker.exists() or any('obsidian' in w.get('class','').lower() for w in clients):break
                time.sleep(.1)
            assert app_marker.exists() or any('obsidian' in w.get('class','').lower() for w in clients)
            mark('PASS: F20 registered callable launches '+('Obsidian' if obsidian else 'a catalog-discovered .desktop application (Obsidian not installed)'))
            result=run(['hyprctl','eval','assert(omabinds_runtime.applied["acceptance_f22"][1].action == omabinds_runtime.groups["|SUPER + V"][1].action, "alias identity mismatch")'])
            assert result.strip()=='ok',result
            mark('PASS: live F22 alias callable is identical to original SUPER+V callable')
            # Alias equality is verified in the Lua runtime unit test; avoid
            # reading or capturing the user's clipboard contents here.
            occupied=copy.deepcopy(candidate);occupied['mappings'][-1]['trigger']='SUPER + V'
            result=c.preview({'state':occupied,'revision':revision(c.state())})
            assert any(x['name']==source['name'] for x in result['conflicts'])
            mark('PASS: conflict names the existing clipboard action before mutation')
            disabled=copy.deepcopy(candidate);disabled['mappings'][-2]['enabled']=False
            c.commit({'state':disabled,'revision':revision(c.state())})
            assert not any('[omabinds:acceptance_f21]' in b['description'] for b in c.live())
            c.commit({'state':candidate,'revision':revision(c.state())})
            mark('PASS: disable and restore mapping')
            run(['hyprctl','reload']);c.config_ok()
            assert sum(b['description'].startswith('[omabinds:acceptance_') for b in c.live())==3
            mark('PASS: mappings persist through independent compositor reload')
        finally:
            if old_data is None:os.environ.pop('XDG_DATA_HOME',None)
            else:os.environ['XDG_DATA_HOME']=old_data
            result=c.commit({'state':saved,'revision':revision(c.state())})
            if result.get('conflicts'):raise Error('Restoration conflict: '+str(result))
            assert semantic(c.live())==before, 'Original effective binding set changed'
            mark('PASS: initial managed state and all original bindings restored')
Path(__file__).resolve().parents[1].joinpath('docs/live-results.txt').write_text('\n'.join(report)+'\n')
