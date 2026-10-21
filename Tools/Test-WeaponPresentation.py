"""Content safety checks: coverage, resources and unchanged weapon gameplay."""
from pathlib import Path
import hashlib
import importlib.util
import json
import unittest

ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'Tools'/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
inventory=load('inventory','Inventory-WeaponPresentation.py')
builder=load('builder','Build-WeaponFlashes.py')
casings=load('casings','Build-WeaponCasings.py')
config=json.loads((ROOT/'References/WeaponPresentation/profiles.json').read_text())


class WeaponContentTests(unittest.TestCase):
    def test_inventory_coverage_and_explicit_omissions(self):
        data=json.loads((ROOT/'References/WeaponPresentation/inventory.json').read_text())
        self.assertEqual(set(config['weapons']),{w['odf'] for w in data['weapons']})
        for name,choice in config['weapons'].items():
            with self.subTest(weapon=name):
                self.assertTrue(choice['decision'])
                if choice['profile']:
                    self.assertIn(choice['profile'],config['profiles'])
                else:
                    self.assertNotEqual(choice['decision'],'authored flash')
        for name in ('gminigun','gtminig','gminigna'):
            self.assertEqual(config['weapons'][name]['profile'],'minigun')
        for name in ('gminisov','gtminis','gtminis2'):
            self.assertEqual(config['weapons'][name]['profile'],'chaingun')
        blue=config['profiles']['minigun']['cool'];red=config['profiles']['chaingun']['cool']
        self.assertGreater(blue[2],blue[0]*5);self.assertGreater(red[0],red[2]*5)

    def test_presentation_only_changes(self):
        baselines=json.loads((ROOT/'References/WeaponPresentation/gameplay-baselines.json').read_text())
        for name,expected in baselines.items():
            with self.subTest(weapon=name):
                text=(ROOT/'ODF'/(name+'.odf')).read_text()
                self.assertEqual(text.count(casings.BEGIN),1)
                self.assertEqual(inventory.parse(text)['weaponclass']['casingtype'],config['weapons'][name]['casing_type'])
                text=casings.strip_block(text)
                if not config['weapons'][name]['profile']:
                    digest=hashlib.sha256(json.dumps(inventory.parse(text),sort_keys=True).encode()).hexdigest()
                    self.assertEqual(digest,expected,'gameplay or stock field changed')
                    continue
                self.assertEqual(text.count(builder.BEGIN),1)
                a=text.index(builder.BEGIN);b=text.index(builder.END,a)+len(builder.END)
                source=text[:a]+text[b:]
                digest=hashlib.sha256(json.dumps(inventory.parse(source),sort_keys=True).encode()).hexdigest()
                self.assertEqual(digest,expected,'gameplay or stock field changed')
                parsed=inventory.parse(text)
                self.assertEqual(parsed['weaponclass']['flashoffset'],'0 0 0','no universal avtank barrel offset')
                self.assertTrue((ROOT/'Assets/Models'/parsed['weaponclass']['flashmesh']).is_file())
                self.assertNotIn('flashmesh',parsed.get('gameobjectclass',{}))

    def test_explicit_casing_choices(self):
        for name,choice in config['weapons'].items():
            self.assertIn(choice['casing_type'],('none','small','medium','large'))
            self.assertTrue(choice['casing_decision'])
        for name in ('asplsmg','gblast','gbolt','ghornet','gmortar','gtechno','gammo'):
            self.assertEqual(config['weapons'][name]['casing_type'],'none',name)
        self.assertEqual(config['weapons']['gminigun']['casing_type'],'small')
        self.assertEqual(config['weapons']['gatstab']['casing_type'],'medium')
        self.assertEqual(config['weapons']['gspstab']['casing_type'],'large')

    def test_generated_assets_and_material_contract(self):
        builder.build(ROOT/'ODF',True)
        casings.build(ROOT/'ODF',True)
        material=(ROOT/'Materials/cr_muzzle.material').read_text()
        program=(ROOT/'Shaders/cr_muzzle.program').read_text()
        for name,p in config['profiles'].items():
            self.assertIn('material CR/Muzzle/'+name+' :',material)
            self.assertGreater(p['duration'],0)
            for channel in ('cool','hot'):
                self.assertEqual(len(p[channel]),3)
                self.assertTrue(all(0<=v<=1 for v in p[channel]))
        for target in ('vs_4_0','ps_4_0','vs_3_0','ps_3_0'):
            self.assertIn(target,program)
        self.assertIn('custom 1344',program)
        self.assertIn('depth_write off',material)
        self.assertTrue((ROOT/'Assets/Textures/crmf_flame.png').is_file())
        # A complete barrel is a candidate only; hull/locomotion roots are never
        # auto-selected or enabled just because they own a muzzle hardpoint.
        self.assertNotIn('recoilName', ''.join((ROOT/'ODF'/(n+'.odf')).read_text()
            for n in config['weapons'] if config['weapons'][n]['profile']))


if __name__=='__main__': unittest.main()
