"""Generate reviewed craft recoil and report every armed CR vehicle/building slot.

No model guessing happens during generation. Explicit reviewed bindings are in
combat-models.json; unsupported rigs retain an actionable mesh-edit decision.
"""
from pathlib import Path
import argparse
import collections
import hashlib
import importlib.util
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'References/WeaponPresentation'
BEGIN, END = '// CR CRAFT RECOIL BEGIN', '// CR CRAFT RECOIL END'
PRODUCERS = {'cannon', 'machinegun', 'mortar', 'snipergun'}


def load_builder():
    spec = importlib.util.spec_from_file_location('flash_builder', ROOT/'Tools/Build-WeaponFlashes.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load_builder()


def documents():
    return {p.stem.lower(): builder.odf_lines(p.read_text(errors='replace'))
            for p in sorted((ROOT/'ODF').glob('*.odf'))}


def armed_units(docs):
    units = {}
    for name, d in docs.items():
        g = d.get('gameobjectclass', {})
        if g.get('classlabel') in ('person', 'armory'):
            continue
        slots = {str(n): {'weapon': g.get('weaponname'+str(n), '').lower(),
                         'hardpoint': g.get('weaponhard'+str(n), '')}
                 for n in range(1, 6)
                 if g.get('weaponname'+str(n), '').lower() not in ('', 'null', 'none')}
        if slots:
            units[name] = {'name': g.get('unitname', ''), 'model': g.get('basename', name).lower(), 'slots': slots}
    return units


def gameplay_digest(parsed):
    parsed = {section: dict(values) for section, values in parsed.items()}
    for k in list(parsed.get('craftclass', {})):
        if k.startswith(('recoil', 'flashoffset')):
            del parsed['craftclass'][k]
    return hashlib.sha256(json.dumps(parsed, sort_keys=True).encode()).hexdigest()


def selected_bindings(unit, docs, policy, choices):
    selected = {}
    for n, slot in unit['slots'].items():
        weapon = docs.get(slot['weapon'], {}).get('weaponclass', {})
        # An omission/unknown weapon is not permission to kick a utility slot.
        if not weapon or not choices.get(slot['weapon'], {}).get('profile'):
            continue
        binding = policy['models'][unit['model']]['bindings'].get(slot['hardpoint'].upper())
        if binding:
            selected[n] = dict(binding)
            selected[n]['kick'] = (None if float(weapon.get('recoilkick', 0)) > 0 else
                                   .25 if weapon.get('classlabel') == 'machinegun' else binding['kick_without_weapon'])
    return selected


def authored_odf(text, selected):
    text = text.replace('\r\n', '\n')
    if BEGIN in text:
        a = text.index(BEGIN); b = text.index(END, a)+len(END)
        if text[b:b+1] == '\n': b += 1
        text = text[:a]+text[b:]
    parsed = builder.odf_lines(text).get('craftclass', {})
    lines = []
    for n, binding in sorted(selected.items()):
        desired = {'recoilName'+n: binding['node'], 'recoilDistance'+n: str(binding['distance']),
                   'recoilReturn'+n: str(binding['return'])}
        if binding['kick'] is not None: desired['recoilKick'+n] = str(binding['kick'])
        # Retain the existing ten documented tank bindings without duplicating keys.
        for key, value in desired.items():
            if key.lower() in parsed:
                same = parsed[key.lower()] == value if key.startswith('recoilName') else float(parsed[key.lower()]) == float(value)
                assert same, f'existing {key} conflicts with reviewed binding'
            else:
                lines.append(f'{key} = "{value}"' if key.startswith('recoilName') else f'{key} = {value}')
    if not lines: return text
    section = re.search(r'(?im)^[ \t]*\[CraftClass\][^\n]*\n', text)
    assert section, 'missing CraftClass for recoil'
    at = section.end()
    if builder.CRAFT_END in text:
        at = text.index(builder.CRAFT_END, at)+len(builder.CRAFT_END)
        if text[at:at+1] == '\n': at += 1
    block = '\n'.join([BEGIN, '// Reviewed independent gun pieces; preserve aiming and deployment parents.',
                       '// Regenerate: python Tools/Build-CombatPresentation.py', *lines, END])+'\n'
    return text[:at]+block+text[at:]


def coverage(docs, units, policy, choices, offsets):
    result = {}
    for name, unit in units.items():
        model = policy['models'][unit['model']]
        selected = selected_bindings(unit, docs, policy, choices)
        rows = {}
        for n, slot in unit['slots'].items():
            w = docs.get(slot['weapon'], {}).get('weaponclass', {})
            choice = choices.get(slot['weapon'], {})
            flash_row = offsets.get(name, {}).get('slots', {}).get(n, {})
            recoil = selected.get(n)
            producer = 'accepted-shot path; live validation pending' if w.get('classlabel') in PRODUCERS else 'native firing producer pending'
            rows[n] = dict(slot, recoil_node=recoil['node'] if recoil else '',
                recoil_distance=recoil['distance'] if recoil else None,
                recoil_effective_kick=(recoil['kick'] if recoil['kick'] is not None else float(w.get('recoilkick', 0))) if recoil else None,
                flash_offset=flash_row.get('offset'),
                flash_status='fitted; live validation pending' if 'offset' in flash_row else flash_row.get('skip', choice.get('decision', 'weapon definition missing')),
                casing_type=choice.get('casing_type', 'unresolved'),
                casing_status=('weapon definition missing' if not choice else
                    'estimated native breech; model port fitting pending' if choice['casing_type'] != 'none' else 'no brass by weapon design'),
                runtime=producer if w else 'weapon definition missing')
        result[name] = dict(unit, category=model['category'], slots=rows)
    return result


def report(data, policy):
    total = collections.Counter()
    for u in data.values():
        for s in u['slots'].values():
            total['slots'] += 1
            total['recoil_slots'] += bool(s['recoil_node'])
            total['flash_slots'] += s['flash_offset'] is not None
            total['casing_slots'] += s['casing_type'] in ('small', 'medium', 'large')
    lines = ['# CR combat weapon effects: implementation and mesh-edit report', '',
        'Initial implementation, 2026-11-04. This report is generated from the current CR source, reviewed model policy and fitted flash data.', '',
        f"**{len(data)} armed ODFs / {len(policy['models'])} models / {total['slots']} equipped slots.** "
        f"Authored recoil: {total['recoil_slots']} slots; fitted flash offsets: {total['flash_slots']} slots; ballistic casing selections: {total['casing_slots']} slots.", '',
        'Scope: CR vehicle/building definitions, including mission variants and utility carriers. People retain per-weapon effects; armories supply weapons. This source-only count excludes stock-only aliases from the earlier 139-definition/52-model audit.', '',
        '## What is implemented', '',
        '- Recoil bindings use reviewed independent gun pieces and preserve the existing tank configurations. Mortar/rocket and minigun slots receive local kick overrides where their weapon supplies none. Weapon gameplay/loadouts are preserved.',
        '- Flash fitting uses explicit visible gun pieces, including sibling bomber guns, non-BG turret tubes and the CRA gun-tower tube. The weapon offset stays zero; craft slots receive geometry-derived corrections.',
        '- All 100 inventoried weapon ODFs already select small/medium/large/none casings. This pass checks every CR loadout against those decisions; plasma/energy/rocket/utility weapons remain casing-free.', '',
        '## Remaining runtime and asset work', '',
        '- These are authored configurations, not native visual acceptance. Existing OpenShim/EXU effect settings, exact-build and single-player gates remain. Beam/guided/targeting/other producer gaps remain explicit in the slot report.',
        '- OpenShim currently supports weapon casingType/casingMesh, not per-craft ejection-port offsets. Brass still uses the firing mount and estimated breech. For a fitted port, add native per-slot local offset/direction support and author matching breech/port markers; do not invent inert ODF keys.',
        '- Recoil is cosmetic. Qualify muzzle flash placement at both rest and kicked poses, aiming, deployment, repeated/simultaneous shots, weapon swaps and scene reload.',
        '- `avartla` selects `gpopguna`, absent from both CR and the extracted stock ODFs. It remains unresolved rather than silently substituting a different weapon.', '',
        '## Units needing mesh or rig edits', '',
        '| Model | Unit ODFs | Work category | Proposed change |', '|---|---|---|---|']
    for name, entry in policy['models'].items():
        if entry['category'] in ('Existing gun piece', 'Utility only'): continue
        members = [n for n, u in data.items() if u['model'] == name]
        brass = any(s['casing_type'] in ('small','medium','large') for n in members for s in data[n]['slots'].values())
        effects = (' Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists.' if brass else
                   ' Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port.')
        lines.append(f"| `{name}` | "+', '.join('`'+n+'`' for n in members)+f" | {entry['category']} | {entry['action']}{effects} |")
    lines += ['', '## Models using existing gun pieces', '', '| Model | Unit ODFs | Binding / remaining detail |', '|---|---|---|']
    for name, entry in policy['models'].items():
        if entry['category'] != 'Existing gun piece': continue
        members = [n for n, u in data.items() if u['model'] == name]
        lines.append(f"| `{name}` | "+', '.join('`'+n+'`' for n in members)+f" | {entry['action']} |")
    lines += ['', '## Every CR unit and equipped slot', '',
              '| ODF | Slot / weapon | Recoil | Flash offset | Casings | Runtime / unresolved placement |', '|---|---|---|---|---|---|']
    for name, unit in data.items():
        for n, slot in unit['slots'].items():
            flash = ' '.join(f'{v:.2f}' for v in slot['flash_offset']) if slot['flash_offset'] is not None else 'pending / omitted'
            notes = slot['runtime']
            if slot['flash_offset'] is None: notes += '; '+slot['flash_status']
            if slot['casing_type'] in ('small', 'medium', 'large'): notes += '; casing port estimated'
            lines.append(f"| `{name}` | {n}: `{slot['weapon']}` | `{slot['recoil_node']}` | {flash} | {slot['casing_type']} | {notes} |")
    return '\n'.join(lines)+'\n', total


def outputs():
    docs = documents(); units = armed_units(docs)
    policy = json.loads((DATA/'combat-models.json').read_text())
    choices = json.loads((DATA/'profiles.json').read_text())['weapons']
    offsets = json.loads(builder.OFFSETS.read_text())['crafts']
    assert set(policy['models']) == {u['model'] for u in units.values()}, 'model policy coverage drift'
    out = {}
    for name, unit in units.items():
        path = ROOT/'ODF'/(name+'.odf')
        out[path] = authored_odf(path.read_text(), selected_bindings(unit, docs, policy, choices)).encode()
    data = coverage(docs, units, policy, choices, offsets)
    text, totals = report(data, policy)
    out[DATA/'combat-coverage.json'] = (json.dumps({'totals':dict(totals), 'units':data}, indent=2)+'\n').encode()
    out[ROOT/'Docs/COMBAT_WEAPON_EFFECTS.md'] = text.encode()
    return out


def verify_models():
    """Optional local proof against actual resolved meshes/VDFs, not guessed node names."""
    from bzmodellibs import legacy, toolbox_root
    sys.path.insert(0, str(toolbox_root()))
    from battlezone.meshes import ogre
    from battlezone.meshes.ogre_skeleton import read_skeleton
    policy = json.loads((DATA/'combat-models.json').read_text())
    lock = json.loads((ROOT/'Shipping/shipping.lock.json').read_text())
    assets = {Path(e['runtime']).name.lower(): ROOT/e['source'].replace('\\','/') for e in lock['files']}
    installed = builder.game_models()
    evidence = {}
    for model, entry in policy['models'].items():
        if not entry['bindings']: continue
        mp, sp = builder.model_files(model, assets, installed)
        mesh = ogre.read_mesh(mp.read_bytes())
        sp = assets.get(mesh.skeleton.lower()) or installed.get(mesh.skeleton.lower()) or sp
        skel = read_skeleton(sp)
        vp = next(p for ext in ('.vdf','.sdf') if (p := assets.get(model+ext) or builder.GAME/'StockODFFiles'/(model+ext)).exists())
        native = legacy.read_vdf(vp) if vp.suffix == '.vdf' else legacy.read_sdf(vp)
        names = {p.name for p in native.band(0)}
        evidence[model] = {'mesh_source':mp.relative_to(ROOT).as_posix() if mp.is_relative_to(ROOT) else None,
                           'skeleton_source':sp.relative_to(ROOT).as_posix() if sp.is_relative_to(ROOT) else None,
                           'native_source':vp.relative_to(ROOT).as_posix() if vp.is_relative_to(ROOT) else None,
                           'mesh_sha256':hashlib.sha256(mp.read_bytes()).hexdigest(),
                           'skeleton_sha256':hashlib.sha256(sp.read_bytes()).hexdigest(),
                           'native_sha256':hashlib.sha256(vp.read_bytes()).hexdigest(), 'nodes':{}}
        for binding in entry['bindings'].values():
            name = binding['node']; bone = skel.bone(name)
            assert 0 < len(name) <= 8 and name in names and bone is not None, (model,name,'native/rendered node missing')
            vertices = builder.barrel_vertices(mesh, bone.handle)
            assert len(vertices) >= 8, (model,name,'no gun geometry')
            for sub in mesh.submeshes:
                assignments = mesh.bone_assignments if sub.uses_shared_vertices else sub.bone_assignments
                weighted = {i for i,b,w in assignments if b == bone.handle and w > 0}
                assert all(w == 1.0 for i,b,w in assignments if b == bone.handle), (model,name,'non-rigid weights')
                assert all(not (set(face) & weighted) or set(face) <= weighted for face in sub.triangles()), (model,name,'mixed-owner triangles')
            track = native.track(name)
            assert not track or len({tuple(round(v,5) for v in pos) for _,pos in track.positions}) <= 1, (model,name,'animated translation')
            assert 0 < binding['distance'] <= 10 and 0 < binding['return'] <= 100
            evidence[model]['nodes'][name] = {'weighted_vertices':len(vertices),'static_native_translation':True,
                                             'rigid_weights':True,'mixed_owner_triangles':0}
    (DATA/'combat-model-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(f'Verified existing weighted/static native gun pieces on {len(evidence)} models')


def build(check=False):
    out = outputs()
    for path, data in out.items():
        if check:
            assert path.exists() and path.read_bytes().replace(b'\r\n',b'\n') == data, str(path.relative_to(ROOT))+' differs; regenerate'
        elif not path.exists() or path.read_bytes().replace(b'\r\n',b'\n') != data:
            path.write_bytes(data)
    return json.loads(out[DATA/'combat-coverage.json'])['totals']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--verify-models', action='store_true', help='verify reviewed pieces against installed stock/CR geometry; record evidence')
    args = parser.parse_args()
    if args.verify_models: verify_models()
    print('Combat presentation:', build(args.check))
