"""Verify complete loadout coverage, gameplay preservation and reviewed recoil ownership."""
from pathlib import Path
import hashlib
import importlib.util
import json
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('combat',ROOT/'Tools/Build-CombatPresentation.py')
combat=importlib.util.module_from_spec(spec);spec.loader.exec_module(combat)


class CombatPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.docs=combat.documents()
        cls.units=combat.armed_units(cls.docs)
        cls.policy=json.loads((combat.DATA/'combat-models.json').read_text())
        cls.choices=json.loads((combat.DATA/'profiles.json').read_text())['weapons']

    def test_all_armed_cr_definitions_preserve_gameplay(self):
        baselines=json.loads((combat.DATA/'craft-gameplay-baselines.json').read_text())
        self.assertEqual(set(self.units),set(baselines))
        for name,expected in baselines.items():
            with self.subTest(unit=name):
                self.assertEqual(combat.gameplay_digest(self.docs[name]),expected)

    def test_complete_model_slot_and_casing_decisions(self):
        self.assertEqual(set(self.policy['models']),{u['model'] for u in self.units.values()})
        data=json.loads((combat.DATA/'combat-coverage.json').read_text())['units']
        self.assertEqual(set(data),set(self.units))
        for name,unit in self.units.items():
            self.assertEqual(set(data[name]['slots']),set(unit['slots']))
            for n,slot in unit['slots'].items():
                with self.subTest(unit=name,slot=n):
                    row=data[name]['slots'][n]
                    self.assertEqual(row['weapon'],slot['weapon'])
                    if slot['weapon'] not in self.choices:
                        self.assertEqual((name,slot['weapon']),('avartla','gpopguna'))
                        self.assertEqual(row['casing_type'],'unresolved')
                        self.assertFalse(row['recoil_node'])
                    else:
                        self.assertEqual(row['casing_type'],self.choices[slot['weapon']]['casing_type'])
                        self.assertEqual(self.docs[slot['weapon']]['weaponclass']['casingtype'],row['casing_type'])

    def test_expected_mechanical_bindings_and_local_machinegun_kick(self):
        for name,n,node in [('abtowe','1','agn11bgb'),('avhraz','2','ahr11bga'),('avhraz','3','ahr11bgb'),
                            ('avturr','1','aDE11blc'),('bvtump','2','bDE11blf'),('cbtowe','1','cgt11tx1')]:
            self.assertEqual(self.docs[name]['craftclass']['recoilname'+n],node)
        self.assertEqual(self.docs['avhraz']['craftclass']['recoilkick2'],'1.0')
        self.assertEqual(self.docs['avturr']['craftclass']['recoilkick1'],'0.25')
        self.assertEqual(self.docs['sbtowea']['craftclass']['recoilkick1'],'0.25')
        self.assertNotIn('recoilkick',self.docs['gtminig']['weaponclass'])
        # An artillery utility or missing weapon cannot inherit an arbitrary barrel kick.
        self.assertNotIn('recoilname1',self.docs['avartla']['craftclass'])
        self.assertNotIn('recoilname2',self.docs['bvhraz']['craftclass'])
        for name in ('avwalk','svwalk','avfigh','avltnk'):
            self.assertFalse(any(k.startswith('recoilname') for k in self.docs[name]['craftclass']))

    def test_native_piece_evidence_and_no_animated_static_binding(self):
        evidence=json.loads((combat.DATA/'combat-model-evidence.json').read_text())
        for name,entry in self.policy['models'].items():
            for b in entry['bindings'].values():
                with self.subTest(model=name,node=b['node']):
                    self.assertLessEqual(len(b['node']),8)
                    proof=evidence[name]['nodes'][b['node']]
                    self.assertGreaterEqual(proof['weighted_vertices'],8)
                    self.assertTrue(proof['static_native_translation'])
                    self.assertTrue(proof['rigid_weights'])
                    self.assertEqual(proof['mixed_owner_triangles'],0)
        for item in evidence.values():
            for resource in ('mesh','skeleton','native'):
                source=item.get(resource+'_source')
                if source:
                    self.assertEqual(hashlib.sha256((ROOT/source).read_bytes()).hexdigest(),item[resource+'_sha256'],
                                     'shipped model changed; reverify its recoil binding')
        self.assertNotIn('svartl',evidence)
        self.assertNotIn('svturr',evidence)

    def test_missing_and_utility_weapons_do_not_get_recoil(self):
        unit={'model':'avhraz','slots':{'2':{'hardpoint':'GR1','weapon':'missing'}}}
        self.assertEqual(combat.selected_bindings(unit,self.docs,self.policy,self.choices),{})
        unit['slots']['2']['weapon']='gsandbag'
        self.assertEqual(combat.selected_bindings(unit,self.docs,self.policy,self.choices),{})

    def test_generated_content_is_repeatable(self):
        combat.build(True)
        for name,unit in self.units.items():
            path=ROOT/'ODF'/(name+'.odf')
            text=path.read_text()
            selected=combat.selected_bindings(unit,self.docs,self.policy,self.choices)
            self.assertEqual(combat.authored_odf(combat.authored_odf(text,selected),selected),text)

    def test_reviewed_muzzle_fit_keeps_bomber_channels_independent(self):
        offsets=json.loads(combat.builder.OFFSETS.read_text())['crafts']
        for n,node in [('2','ahr11bga'),('3','ahr11bgb')]:
            row=offsets['avhraz']['slots'][n]
            self.assertTrue(row['reviewed_barrel'])
            self.assertEqual(row['barrel'],node)
            self.assertGreater(row['offset'][2],1)
        # Shared weapon definitions retain zero craft-specific offset.
        self.assertEqual(self.docs['grktbomb']['weaponclass']['flashoffset'],'0 0 0')


if __name__=='__main__': unittest.main()
