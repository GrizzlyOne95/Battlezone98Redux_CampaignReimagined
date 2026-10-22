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
                self.assertEqual(text.count(builder.RECOIL_BEGIN),1 if builder.wants_kick(text) else 0)
                text=builder.strip_recoil(text)
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

    def test_craft_flash_offsets(self):
        data=json.loads(builder.OFFSETS.read_text())['crafts']
        live=builder.craft_slots(ROOT/'ODF',builder.flash_weapons(config))
        self.assertEqual(set(data),set(live),'every flash-carrying craft is measured or explicitly skipped')
        written=0
        for craft,entry in data.items():
            text=(ROOT/'ODF'/(craft+'.odf')).read_text()
            parsed=inventory.parse(text)
            keys={k:v for k,v in parsed.get('craftclass',{}).items() if k.startswith('flashoffset')}
            expected={}
            for n,row in entry['slots'].items():
                with self.subTest(craft=craft,slot=n):
                    self.assertEqual(row['weapon'],live[craft]['slots'][int(n)][0])
                    self.assertNotEqual('offset' in row,'skip' in row,'offset xor skip reason')
                    if 'offset' in row:
                        self.assertGreaterEqual(row['offset'][2],builder.MIN_TIP)
                        self.assertTrue(all(abs(v)<=20 for v in row['offset']))
                        expected['flashoffset'+n]=' '.join(f'{v:.2f}' for v in row['offset'])
            self.assertEqual(keys,expected,craft)
            self.assertEqual(text.count(builder.CRAFT_BEGIN),1 if expected else 0)
            written+=len(expected)
        self.assertGreater(written,0)
        # The live-fitted avtank barrel tip must be reproduced from the mesh.
        self.assertEqual(inventory.parse((ROOT/'ODF/avtank.odf').read_text())['craftclass']['flashoffset1'],'0.20 0.10 2.41')
        # Weapons keep their natural zero offset; a craft key never lands on a non-flash slot.
        for craft in data:
            game=inventory.parse((ROOT/'ODF'/(craft+'.odf')).read_text())
            for key in game.get('craftclass',{}):
                if key.startswith('flashoffset'):
                    weapon=game['gameobjectclass']['weaponname'+key[len('flashoffset'):]].lower()
                    self.assertIn(weapon,builder.flash_weapons(config))

    def test_weapon_recoil_kick_is_opt_in(self):
        kicked=set()
        for path in sorted((ROOT/'ODF').glob('*.odf')):
            text=path.read_text(errors='replace')
            weapon=inventory.parse(text).get('weaponclass')
            if not weapon: continue
            with self.subTest(weapon=path.stem):
                if weapon.get('classlabel','').lower()=='machinegun':
                    self.assertNotIn('recoilkick',weapon,'no machinegun or minigun kicks')
                if weapon.get('wpncategory','').upper()=='CANN' and weapon.get('classlabel','').lower()!='machinegun':
                    self.assertEqual(weapon.get('recoilkick'),builder.CANNON_KICK,'every cannon-category weapon kicks')
                    self.assertEqual(text.count(builder.RECOIL_BEGIN),1)
                    kicked.add(path.stem.lower())
                else:
                    self.assertNotIn('recoilkick',weapon)
        self.assertTrue({'gatstab','gspstab','gsatstab','ga7stab'}<=kicked)
        for name in ('gminigun','gtminig','gminigna','gminisov','gtminis'):
            self.assertNotIn('recoilkick',inventory.parse((ROOT/'ODF'/(name+'.odf')).read_text())['weaponclass'])

    def test_every_recoil_slot_default_weapon_has_kick(self):
        crafts=set('avtank avtamp avdemo bvtank bvtanka svtank svtanka svtas8 svtk13 svtnk7'.split())
        found=set()
        for path in sorted((ROOT/'ODF').glob('*.odf')):
            parsed=inventory.parse(path.read_text(errors='replace'))
            craft=parsed.get('craftclass',{})
            slots=[k[len('recoilname'):] for k in craft if k.startswith('recoilname')]
            if not slots: continue
            found.add(path.stem.lower())
            for n in slots:
                with self.subTest(craft=path.stem,slot=n):
                    weapon=parsed['gameobjectclass']['weaponname'+n].lower()
                    kick=craft.get('recoilkick'+n)
                    if kick is None:
                        kick=inventory.parse((ROOT/'ODF'/(weapon+'.odf')).read_text()).get('weaponclass',{}).get('recoilkick')
                    self.assertEqual(float(kick or 0),1.0,'recoil slot default weapon kicks at 1.0')
        self.assertEqual(found,crafts)

    def test_explicit_casing_choices(self):
        for name,choice in config['weapons'].items():
            self.assertIn(choice['casing_type'],('none','small','medium','large'))
            self.assertTrue(choice['casing_decision'])
        for name in ('asplsmg','gblast','gbolt','ghornet','gmortar','gtechno','gammo'):
            self.assertEqual(config['weapons'][name]['casing_type'],'none',name)
        self.assertEqual(config['weapons']['gminigun']['casing_type'],'small')
        self.assertEqual(config['weapons']['gatstab']['casing_type'],'medium')
        self.assertEqual(config['weapons']['gspstab']['casing_type'],'large')
        example=(ROOT/'ODF/gminigun.odf').read_text()
        self.assertIn('// casingMesh = "mymod_brass.mesh"',example)
        self.assertIn('unit length 1 along local +Z',example)
        selected=dict(config['weapons']['gminigun'],casing_mesh='MyMod/Brass.mesh')
        generated=casings.authored_odf(example,selected)
        self.assertEqual(inventory.parse(generated)['weaponclass']['casingmesh'],'MyMod/Brass.mesh')
        self.assertEqual(casings.authored_odf(generated,selected),generated)

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
