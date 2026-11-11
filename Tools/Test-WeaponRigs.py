"""Final runtime assets: closure, skin/clip ownership, cockpit copies and port safety.

Original cockpit-builder tests explicitly validate their pinned pre-rig stage;
this suite validates the real post-rig files selected by the shipping lock.
"""
from pathlib import Path
import dataclasses, hashlib, json, sys, unittest
import numpy as np
import weaponrigs as wr
import hardpointbones as hpbones
import ogrelayout

ROOT=wr.ROOT;REF=ROOT/'References/WeaponRigs'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

class WeaponRigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config=json.loads((REF/'models.json').read_text());cls.records=json.loads((REF/'build.json').read_text())

    def test_requested_models_and_exclusion(self):
        expected=set('avfigh avltnk avrckt avtest avwalk bvltnk bvraz bvrckt bvrdev bvwalk cblasr cvartl cvfigh cvhraz cvhtnk cvltnk cvrckt cvtnk cvturr svartl svfigh svhraz svltnk svrckt svtank svturr svwalk'.split())
        self.assertEqual(set(self.config['models']),expected)
        self.assertEqual(set(self.records),expected)
        self.assertNotIn('svsav',self.records)
        self.assertIn('utility',self.config['excluded'])

    def test_exported_hashes_geometry_and_closed_moving_parts(self):
        for model,record in self.records.items():
            for relative,expected in record['outputs'].items():
                with self.subTest(model=model,file=relative):
                    path=ROOT/relative;self.assertEqual(digest(path),expected)
                    if path.suffix!='.mesh':continue
                    self.assertFalse(ogrelayout.mixed_skinned_submeshes(path.read_bytes()),f'{relative}: position/normal stream must not carry UVs or tangents')
                    mesh=wr.ogre.read_mesh(path.read_bytes());skel=wr.read_skeleton(ROOT/'Assets/Models'/mesh.skeleton)
                    names={b.handle:b.name for b in skel.bones};pieces={}
                    for sub in mesh.submeshes:
                        g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry
                        data=np.asarray(g.attribute(1));self.assertTrue(np.isfinite(data).all())
                        normals=np.asarray(g.attribute(4));self.assertTrue(np.isfinite(normals).all())
                        for e in g.elements:
                            if e.semantic in (7,9):self.assertTrue(np.isfinite(np.asarray(g.attribute(e.semantic,e.index))).all())
                        assignments=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments
                        owners={i:b for i,b,w in assignments if w==1}
                        for face in sub.triangles():
                            b=owners.get(face[0]);name=names.get(b,'')
                            if not name.startswith('crgun_'):continue
                            self.assertTrue(all(owners.get(i)==b for i in face))
                            tri=data[list(face)];self.assertGreater(np.linalg.norm(np.cross(tri[1]-tri[0],tri[2]-tri[0])),1e-10)
                            pieces.setdefault(name,[]).append(tri)
                    for name,faces in pieces.items():
                        self.assertFalse(wr.boundary(faces)[0],f'{model}/{path.name}/{name}: exposed edge')

    def test_original_bind_poses_and_animation_tracks_survive(self):
        for model,record in self.records.items():
            pairs=[(ROOT/'Assets/Models'/(model+'_recoil.skeleton'),record['source'])]
            if record.get('cockpit_source'):pairs.append((ROOT/'Assets/Models'/(model+'_cockpit_recoil.skeleton'),record['cockpit_source']))
            moved=record.get('hardpoints',{})
            receipt=hpbones.receipt(model)
            self.assertEqual(set(moved),{p['name'] for p in receipt['parts']} if receipt else set(),model)
            cockpit_moved=record.get('cockpit_hardpoints',{})
            # Cockpit posing is opt-in per model; the receipt must follow the flag.
            self.assertEqual(bool(cockpit_moved),bool(self.config['models'][model].get('cockpit_hardpoints')) and bool(moved),model+' cockpit_hardpoints opt-in')
            if cockpit_moved:self.assertEqual(cockpit_moved,moved,model+' cockpit hardpoints match the world rig')
            for path,source in pairs:
                skel=wr.read_skeleton(path)
                self.assertTrue(set(source['animations']) <= {a.name for a in skel.animations})
                rehung=path.name==model+'_recoil.skeleton' or (bool(cockpit_moved) and path.name==model+'_cockpit_recoil.skeleton')
                if rehung:
                    for part in receipt['parts'] if receipt else ():
                        name=part['name'];bone=skel.bone(name);pose=moved[name]
                        self.assertEqual(skel.bones[bone.parent].name,part['owner'],f'{model}/{name} owner')
                        self.assertTrue(np.allclose(bone.position,hpbones.MIRROR@np.asarray(part['matrix'][9:12]),atol=2e-5),f'{model}/{name} receipt position')
                        self.assertTrue(np.allclose(bone.orientation,pose['orientation'],atol=2e-5),f'{model}/{name} receipt rotation')
                        self.assertFalse(any(t.bone==bone.handle for a in skel.animations for t in a.tracks),f'{model}/{name} animated')
                for name,(position,rotation) in source['bind_poses'].items():
                    if name in moved and rehung:continue
                    bone=skel.bone(name);self.assertIsNotNone(bone)
                    p,q=wr.flash.bone_world(skel,bone.handle)
                    self.assertTrue(np.allclose(p,position,atol=2e-5),f'{model}/{name} bind moved')
                    for axis in np.eye(3):self.assertTrue(np.allclose(wr.flash._rotate(q,axis),wr.flash._rotate(rotation,axis),atol=2e-5))
                for a in skel.animations:
                    if a.name in source['animations']:
                        h=hashlib.sha256(json.dumps(dataclasses.asdict(a),sort_keys=True).encode()).hexdigest()
                        self.assertEqual(h,source['animations'][a.name])

    def test_independent_four_barrels_and_spin_in_both_views(self):
        self.assertEqual(len(self.config['models']['cvturr']['channels']),4)
        for view in ('world','cockpit'):
            self.assertEqual(len(self.records['cvturr'][view]),4)
            self.assertTrue(all(p['triangles']>0 for p in self.records['cvturr'][view]))
        for model in self.records:
            world=wr.read_skeleton(ROOT/'Assets/Models'/(model+'_recoil.skeleton'))
            cp=wr.read_skeleton(ROOT/'Assets/Models'/(model+'_cockpit_recoil.skeleton')) if self.records[model]['cockpit'] else None
            for channel in self.config['models'][model]['channels']:
                clip=next(a for a in world.animations if a.name==channel['clip']);self.assertTrue(clip.tracks)
                if cp:
                    twin=next(a for a in cp.animations if a.name==channel['clip']);self.assertEqual(clip.length,twin.length)
                if model=='cvfigh':
                    self.assertLess(channel['lo'][2],1.9) # Full exposed tubes, not only the forward tips.
                    for track in clip.tracks:
                        self.assertEqual(len(track.keyframes),5)
                        self.assertTrue(all(k.translation==(0,0,0) for k in track.keyframes))

    def test_outboard_scout_ports_and_hull_clearance(self):
        for model,record in self.records.items():
            mesh=wr.ogre.read_mesh((ROOT/'Assets/ModelFixes'/(model+'.mesh')).read_bytes());skel=wr.read_skeleton(ROOT/'Assets/Models'/mesh.skeleton)
            def world(handle):
                b=skel.bones[handle]
                while b is not None:
                    if len(b.name)>3 and b.name[3]=='2':return False
                    b=skel.bones[b.parent] if b.parent is not None else None
                return True
            faces=[]
            for sub in mesh.submeshes:
                g=mesh.shared_geometry if sub.uses_shared_vertices else sub.geometry;p=np.asarray(g.attribute(1))
                a=mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments;owners={i:b for i,b,w in a if w>.99}
                faces.extend(p[list(f)] for f in sub.triangles() if all(i in owners and world(owners[i]) for i in f))
            tri=np.asarray(faces)
            for hard,binding in record['bindings'].items():
                self.assertTrue(binding['casing_jitter_rays_clear'])
                self.assertGreaterEqual(wr.surface_clearance(np.asarray(binding['port_world']),tri),.2499)
                self.assertTrue(all(abs(v)<=20 for v in binding['casing_offset']))
            if model in ('avfigh','bvraz'):
                a=record['bindings']['GC1'];b=record['bindings']['GC2']
                self.assertGreater(a['direction_world'][0],.8);self.assertLess(b['direction_world'][0],-.8)
                self.assertGreater(a['port_world'][0],0);self.assertLess(b['port_world'][0],0)

    def test_reviewed_visible_guns_instead_of_marker_housing(self):
        for model,parent in [('avfigh','ARA11BDA'),('bvraz','bRA11BDA')]:
            for piece in self.records[model]['world']:
                self.assertTrue(piece['helpers'])
                self.assertTrue(all(h['parent']==parent for h in piece['helpers']))
            for b in self.records[model]['bindings'].values():
                self.assertLess(b['tip_world'][2],1.3) # Side rail guns; nose markers are at Z=2.6.
        for ch in self.config['models']['svfigh']['channels']:
            self.assertGreater(ch['hi'][0]-ch['lo'][0],.5) # Include the outer gun ring.
        a=self.records['svhraz']['bindings']['GR1']['tip_world']
        b=self.records['svhraz']['bindings']['GR2']['tip_world']
        self.assertGreater(abs(a[0]-b[0]),1.0) # Distinct large forward apertures.

    def test_svfigh_cannon_tip_recoil_and_cockpit_pod(self):
        # Owner review: the black cannon tips must visibly recoil (2.5 cm read as
        # static), and first person must show the hardpoint rocket pod.
        odf=(ROOT/'ODF/svfigh.odf').read_text()
        record=self.records['svfigh']
        for n,(hard,clip) in enumerate([('GC1','cr_fire_1'),('GC2','cr_fire_2')],1):
            self.assertIn(f'weaponHard{n} = "{hard}"',odf);self.assertIn(f'recoilAnimation{n} = "{clip}"',odf);self.assertIn(f'recoilCockpit{n} = true',odf)
            self.assertIn(hard,record['bindings'])
            for name in ('svfigh_recoil.skeleton','svfigh_cockpit_recoil.skeleton'):
                skel=wr.read_skeleton(ROOT/'Assets/Models'/name);anim=next(a for a in skel.animations if a.name==clip)
                self.assertTrue(anim.tracks and all(skel.bones[t.bone].name.startswith('crgun_') for t in anim.tracks),name)
                travel=max(np.linalg.norm(k.translation) for t in anim.tracks for k in t.keyframes)
                self.assertGreaterEqual(travel,.07,f'{name}/{clip} tip travel')
        exterior=wr.ogre.read_mesh((ROOT/'Assets/ModelFixes/svfigh.mesh').read_bytes())
        cockpit=wr.ogre.read_mesh((ROOT/'Assets/Models/svfigh_cockpit.mesh').read_bytes())
        skel=wr.read_skeleton(ROOT/'Assets/Models'/cockpit.skeleton)
        def sub(mesh,material):return next((s for s in mesh.submeshes if s.material==material),None)
        source=sub(exterior,'svfigh_hpmount');pod=sub(cockpit,'CRV/svfighCombatHpmount')
        self.assertIsNotNone(pod,'cockpit shows the hardpoint rocket pod')
        self.assertEqual(len(list(pod.triangles())),len(list(source.triangles())))
        self.assertTrue(np.allclose(np.asarray(pod.geometry.attribute(1)).min(0),np.asarray(source.geometry.attribute(1)).min(0),atol=1e-5),'pod at its native position')
        self.assertEqual({skel.bones[b].name for _,b,_ in pod.bone_assignments},{'SFL11ROR'},'pod rolls with the nose')

    def test_opted_in_cockpit_hardpoints_match_world_rig(self):
        # models.json "cockpit_hardpoints": true poses the cockpit's receipt hardpoints
        # exactly where the world rig puts them, so first-person muzzles match.
        opted=[m for m,e in self.config['models'].items() if e.get('cockpit_hardpoints')]
        self.assertIn('svfigh',opted)
        for model in opted:
            receipt=hpbones.receipt(model);self.assertIsNotNone(receipt,model)
            world=wr.read_skeleton(ROOT/'Assets/Models'/(model+'_recoil.skeleton'))
            cockpit=wr.read_skeleton(ROOT/'Assets/Models'/(model+'_cockpit_recoil.skeleton'))
            for part in receipt['parts']:
                for name in (part['name'],part['owner']):
                    a=wr.flash.bone_world(world,world.bone(name).handle);b=wr.flash.bone_world(cockpit,cockpit.bone(name).handle)
                    self.assertTrue(np.allclose(a[0],b[0],atol=1e-4),f'{model}/{name} first-person position')
                    self.assertTrue(np.allclose(np.abs(np.dot(a[1],b[1])),1,atol=1e-5),f'{model}/{name} first-person rotation')

if __name__=='__main__':unittest.main()
