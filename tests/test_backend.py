import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from backend.omabinds import Controller, Error, canonical, encode_state, lua_utf8, revision, apps, openable_plugins, plugin_icon


def mapping(key='F20', **kwargs):
    return dict(id='one', name='Test café 🐈', trigger=key, enabled=True,
                action={'kind': 'command', 'command': "printf 'hello'"}, **kwargs)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.c = Controller(self.tmp.name)
        self.c.dir.mkdir()
        self.c.main.parent.mkdir()
        self.c.main.write_text('-- personal configuration\n')

    def test_key_canonicalization(self):
        self.assertEqual(canonical('shift + mod4 + v'), 'SUPER + SHIFT + V')
        self.assertEqual(canonical('F22'), 'F22')
        self.assertEqual(canonical('xf86audioplay'), 'XF86AudioPlay')
        self.assertEqual(canonical('CTRL + plus'), 'CTRL + plus')
        for key in ('badkey', 'F20\nhl.exec_cmd("bad")', 'SUPER +', 'MOD9 + V', 'code:1'):
            with self.assertRaises(Error): canonical(key)

    def test_lua_roundtrip_injection_and_unicode(self):
        m = mapping()
        m['action']['command'] = '\n"; os.execute("touch /tmp/NOT_ALLOWED"); --\\ 🐈'
        state = {'version': 1, 'mappings': [m]}
        self.c.statefile.write_text(encode_state(state))
        result = subprocess.run(['lua', '-e', 'local s=dofile(' + lua_utf8(str(self.c.statefile)) + '); io.write(s.mappings[1].action.command)'], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, m['action']['command'])
        self.assertEqual(self.c.state(), state)

    def test_validation_rejects_invalid_import(self):
        for state in ({'version': 2, 'mappings': []}, {'version':1, 'mappings':[mapping(), mapping()]}, {'version':1,'mappings':[dict(mapping(),enabled='yes')]}):
            with self.assertRaises(Error): self.c.validate(state)

    def test_plugin_kinds_and_validation(self):
        entries = [
            {'id':'example.panel','name':'Panel','kinds':['panel'],'enabled':True},
            {'id':'example.menu','name':'Menu','kinds':['menu','bar-widget'],'enabled':True},
            {'id':'example.overlay','name':'Overlay','kinds':['service','overlay'],'enabled':True},
            {'id':'example.widget','name':'Widget','kinds':['bar-widget'],'enabled':True},
            {'id':'example.service','name':'Service','kinds':['service'],'enabled':True},
            {'id':'example.bar','name':'Bar','kinds':['bar'],'enabled':True},
            {'id':'example.disabled','name':'Disabled','kinds':['panel'],'enabled':False},
        ]
        widget = Path(self.tmp.name)/'omarchy/plugins/example.widget'
        widget.mkdir(parents=True)
        (widget/'manifest.json').write_text(json.dumps({'entryPoints': {'barWidget': 'BarWidget.qml'}}))
        (widget/'BarWidget.qml').write_text('BarWidget { function open() { panel.open() } }')
        with patch.dict(os.environ, XDG_CONFIG_HOME=self.tmp.name), patch('backend.omabinds.run', return_value=json.dumps(entries)) as shell:
            self.assertEqual(set(openable_plugins()), {'example.panel','example.menu','example.overlay','example.widget'})
            m = mapping()
            m['action'] = {'kind':'plugin','plugin':'example.panel','command':'touch /tmp/untrusted'}
            self.c.validate({'version':1,'mappings':[m]})
            self.assertEqual(m['action']['command'], "omarchy-shell shell summon example.panel '{}'")
            m['action'] = {'kind':'plugin','plugin':'example.widget'}
            self.c.validate({'version':1,'mappings':[m]})
            self.assertEqual(m['action']['command'], "omarchy-shell shell summon example.widget '{}'")
            for plugin in ('example.service','example.bar','example.disabled','missing'):
                m['action'] = {'kind':'plugin','plugin':plugin}
                with self.assertRaisesRegex(Error, 'unavailable'):
                    self.c.validate({'version':1,'mappings':[m]})
            m['action'] = {'kind':'plugin','plugin':'example.panel; touch /tmp/untrusted'}
            with self.assertRaisesRegex(Error, 'identifier'):
                self.c.validate({'version':1,'mappings':[m]})
            m['enabled']=False
            m['action']={'kind':'plugin','plugin':'example.disabled','command':'untrusted'}
            self.c.validate({'version':1,'mappings':[m]})
            self.assertEqual(m['action']['command'], '')
            self.assertTrue(shell.called)

    def test_plugin_icon_from_installed_assets(self):
        icon = Path(self.tmp.name)/'omarchy/plugins/example.panel/assets/icon.svg'
        icon.parent.mkdir(parents=True)
        icon.write_text('<svg/>')
        with patch.dict(os.environ, XDG_CONFIG_HOME=self.tmp.name):
            self.assertEqual(plugin_icon('example.panel'), icon.as_uri())
            self.assertEqual(plugin_icon('missing'), '')
            self.assertEqual(plugin_icon('..'), '')

    def test_command_syntax_checked_without_execution(self):
        m=mapping();m['action']['command']='echo "unterminated'
        with self.assertRaises(Error):self.c.validate({'version':1,'mappings':[m]})
        marker=Path(self.tmp.name)/'never-execute'
        m['action']['command']='touch '+str(marker)
        self.c.validate({'version':1,'mappings':[m]})
        self.assertFalse(marker.exists())

    def test_changed_trigger_drops_replacement_consent(self):
        self.c.catalogfile.write_text(json.dumps({'bindings':[{'id':'|F20','trigger':'F20','signature':'sig'}]}))
        m=mapping('F21',replaces={'|F20':'sig'})
        with patch.object(self.c,'live',return_value=[]):
            result=self.c.preview({'state':{'version':1,'mappings':[m]},'revision':revision(self.c.state())})
        self.assertEqual(result['state']['mappings'][0]['replaces'],{})

    def test_system_edit_is_bound_to_original_and_restorable(self):
        row={'id':'|F20','trigger':'F20','name':'Original','signature':'sig','supported':True,'submap':''}
        self.c.catalogfile.write_text(json.dumps({'bindings':[row]}))
        m=mapping(replaces={'|F20':'sig'},systemSource={'id':'|F20','signature':'sig'})
        m['name']='Original'
        state={'version':1,'mappings':[m]}
        with patch.object(self.c,'live',return_value=[]):
            self.assertEqual(self.c.preview({'state':copy.deepcopy(state),'revision':revision(self.c.state())})['conflicts'],[])
            moved=self.c.preview({'state':{'version':1,'mappings':[dict(m,trigger='F21')]},'revision':revision(self.c.state())})
            self.assertEqual(moved['conflicts'],[])
            self.assertEqual(moved['state']['mappings'][0]['replaces'],{'|F20':'sig'})
            for changed in (dict(m, name='Renamed'), dict(m, replaces={}),
                            dict(m, replaces={'|F20':'sig','|F21':'sig'})):
                with self.assertRaises(Error):
                    self.c.preview({'state':{'version':1,'mappings':[changed]},'revision':revision(self.c.state())})
            row['signature']='new signature'
            self.c.catalogfile.write_text(json.dumps({'bindings':[row]}))
            with self.assertRaisesRegex(Error,'changed'):
                self.c.preview({'state':copy.deepcopy(state),'revision':revision(self.c.state())})
            m['enabled']=False
            self.assertEqual(self.c.preview({'state':state,'revision':revision(self.c.state())})['conflicts'],[])

    def test_system_edit_rechecked_after_verify(self):
        self.c.main.write_text('-- BEGIN omabinds CAPTURE\n')
        old=encode_state(self.c.state()); self.c.statefile.write_text(old)
        row={'id':'|F20','trigger':'F20','name':'Original','signature':'sig','supported':True,'submap':''}
        self.c.catalogfile.write_text(json.dumps({'bindings':[row]}))
        m=mapping(replaces={'|F20':'sig'},systemSource={'id':'|F20','signature':'sig'})
        m['name']='Original'
        def change_source(*args):
            row['signature']='changed'
            self.c.catalogfile.write_text(json.dumps({'bindings':[row]}))
        with patch.object(self.c,'verify',side_effect=change_source), patch.object(self.c,'live',return_value=[]):
            with self.assertRaisesRegex(Error,'changed'):
                self.c.commit({'state':{'version':1,'mappings':[m]},'revision':revision(self.c.state())})
        self.assertEqual(self.c.statefile.read_text(),old)
        self.assertFalse(self.c.journal.exists())

    def test_dynamic_conflict_is_not_mistaken_for_original(self):
        self.c.catalogfile.write_text(json.dumps({'bindings':[{'id':'|F20','trigger':'F20','name':'Original','signature':'sig','runtime':[{'dispatcher':'__lua','arg':'5'}]}]}))
        dynamic=[{'key':'F20','keycode':0,'modmask':0,'description':'Dynamic action','dispatcher':'__lua','arg':'99'}]
        with patch.object(self.c,'live',return_value=dynamic):
            conflicts=self.c.conflicts({'mappings':[mapping(replaces={'|F20':'sig'})]})
        self.assertEqual(conflicts[0]['name'],'Dynamic action')
        self.assertTrue(conflicts[0]['dynamic'])

    def test_conflict_precedes_mutation(self):
        self.c.catalogfile.write_text(json.dumps({'bindings':[{'id':'|F20','trigger':'F20','name':'Existing action','signature':'sig','submap':''}]}))
        with patch.object(self.c, 'live', return_value=[]):
            found = self.c.preview({'state':{'version':1,'mappings':[mapping()]},'revision':revision(self.c.state())})
        self.assertEqual(found['conflicts'][0]['name'], 'Existing action')
        self.assertFalse(self.c.statefile.exists())

    def test_snapshot_does_not_count_moved_alias_as_original(self):
        row={'id':'|SUPER + ALT + S','trigger':'SUPER + ALT + S','name':'Original',
             'signature':'sig','submap':'','runtime':[{'dispatcher':'__lua','arg':'5'}]}
        self.c.catalogfile.write_text(json.dumps({'bindings':[row], 'warnings':[]}))
        edited=mapping('SUPER + SHIFT + S', replaces={row['id']:row['signature']})
        edited['id']='edit'
        self.c.statefile.write_text(encode_state({'version':1,'mappings':[edited]}))
        original={'key':'S','keycode':0,'modmask':72,'submap':'',
                  'description':'Original','dispatcher':'__lua','arg':'5'}
        moved=dict(original,modmask=65,arg='99',description='[omabinds:edit] Original')
        with patch.object(self.c,'live',return_value=[original,moved]), patch('backend.omabinds.run',return_value='{"commands":[]}'):
            catalog=self.c.snapshot()['catalog']['bindings']
            self.assertFalse(catalog[0]['effective'], 'hyprctl also lists disabled original handles')
            self.assertEqual(len(catalog),1)
        with patch.object(self.c,'live',return_value=[original]), patch('backend.omabinds.run',return_value='{"commands":[]}'):
            self.assertTrue(self.c.snapshot()['catalog']['bindings'][0]['effective'], 'failed override must not hide the original')
        edited['enabled']=False
        self.c.statefile.write_text(encode_state({'version':1,'mappings':[edited]}))
        with patch.object(self.c,'live',return_value=[original]), patch('backend.omabinds.run',return_value='{"commands":[]}'):
            self.assertTrue(self.c.snapshot()['catalog']['bindings'][0]['effective'], 'disabling the edit restores the system row')

    def test_disabled_binding_does_not_conflict(self):
        a, b = mapping(), dict(mapping(), id='two', enabled=False)
        with patch.object(self.c, 'live', return_value=[]):
            self.assertEqual(self.c.conflicts({'mappings':[a,b]}), [])

    def test_concurrent_edit_rejected(self):
        with self.assertRaisesRegex(Error, 'changed'):
            self.c.preview({'state':{'version':1,'mappings':[]},'revision':'old'})

    def test_rollback_after_reload_error(self):
        self.c.main.write_text('-- BEGIN omabinds CAPTURE\n')
        original = encode_state(self.c.state())
        self.c.statefile.write_text(original)
        req={'state':{'version':1,'mappings':[mapping()]},'revision':revision(self.c.state())}
        with patch.object(self.c, 'verify'), patch.object(self.c, 'live', return_value=[]), patch.object(self.c, 'config_ok', side_effect=[Error('invalid'), None]), patch('backend.omabinds.run',return_value=''):
            with self.assertRaisesRegex(Error, 'restored'): self.c.commit(req)
        self.assertEqual(self.c.statefile.read_text(),original)
        self.assertFalse(self.c.journal.exists())

    def test_failed_preflight_never_writes(self):
        self.c.main.write_text('-- BEGIN omabinds CAPTURE\n')
        original=encode_state(self.c.state()); self.c.statefile.write_text(original)
        req={'state':{'version':1,'mappings':[mapping()]},'revision':revision(self.c.state())}
        with patch.object(self.c,'config_ok'),patch.object(self.c,'live',return_value=[]),patch.object(self.c,'verify',side_effect=Error('bad')):
            with self.assertRaises(Error):self.c.commit(req)
        self.assertEqual(self.c.statefile.read_text(),original)
        self.assertFalse(self.c.journal.exists())

    def test_reinstall_ignores_historical_configerrors_before_reload(self):
        self.c.main.write_text('-- BEGIN omabinds CAPTURE\n')
        with patch.object(self.c, 'verify') as verify, \
             patch.object(self.c, 'config_ok') as config_ok, \
             patch('backend.omabinds.run', return_value='') as run_mock:
            self.c.install()
        verify.assert_called_once_with()
        config_ok.assert_called_once_with()
        run_mock.assert_called_once_with(['hyprctl', 'reload'])

    def test_recover_interrupted_transaction(self):
        old=encode_state(self.c.state())
        self.c.journal.write_text(json.dumps({'previous':old}))
        self.c.statefile.write_text(encode_state({'version':1,'mappings':[mapping()]}))
        with patch.object(self.c,'config_ok'),patch('backend.omabinds.run',return_value=''):self.c.recover()
        self.assertEqual(self.c.statefile.read_text(),old)

    def test_uninstall_preserves_later_edits(self):
        start,end=self.c.hooks();self.c.main.write_text(start+'-- user\n'+end+'-- later edit\n')
        with patch.object(self.c,'verify'),patch.object(self.c,'config_ok'),patch('backend.omabinds.run',return_value=''):self.c.uninstall()
        self.assertEqual(self.c.main.read_text(),'-- user\n-- later edit\n')

    def test_app_catalog_masks_hidden_entries(self):
        root=Path(self.tmp.name); local=root/'local/applications';system=root/'system/applications'
        local.mkdir(parents=True);system.mkdir(parents=True)
        (local/'hidden.desktop').write_text('[Desktop Entry]\nType=Application\nHidden=true\n')
        (system/'hidden.desktop').write_text('[Desktop Entry]\nType=Application\nName=Hidden app\nExec=true\n')
        (system/'real.desktop').write_text('[Desktop Entry]\nType=Application\nName=Real app\nExec=true %U\nIcon=example\n')
        with patch.dict(os.environ,{'XDG_DATA_HOME':str(root/'local'),'XDG_DATA_DIRS':str(root/'system')}):
            self.assertEqual([a['name'] for a in apps()],['Real app'])

    def test_setup_status_requires_lua_and_owned_launcher(self):
        with patch.dict(os.environ, {'XDG_DATA_HOME': str(Path(self.tmp.name)/'data')}):
            self.assertEqual(self.c.setup_status(), {'lua': False, 'launcher': False, 'ready': False})
            self.c.main.write_text('-- BEGIN omabinds CAPTURE\n')
            self.assertEqual(self.c.setup_status(), {'lua': True, 'launcher': False, 'ready': False})
            self.c.launcher.parent.mkdir(parents=True)
            self.c.launcher.write_text('[Desktop Entry]\nX-omabinds-Owned=true\n')
            self.assertEqual(self.c.setup_status(), {'lua': True, 'launcher': True, 'ready': True})

if __name__ == '__main__': unittest.main()
