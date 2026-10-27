"""Point CR_BZBase materials at baked ACT maps and ship the textures.

  python Tools/Apply-ActMaps.py <act dir> [--dry]

<act dir> is the output of BZ98RBlenderToolKit scripts/sp_bake/act_pack.py:
<material>_ACT.dds per material plus cr_act_neutral.dds.  For every material
block that inherits CR_BZBase or CR_BZBaseCockpit (directly or through
another material) and has a map, this adds or updates

    set_texture_alias ACTMap <material>_ACT.dds

after the block's other aliases, copies the DDS into Assets/Textures and adds
it to Shipping/shipping.lock.json.  The neutral default is shipped too; the
actMap texture_unit in CR_BZBase.material falls back to it.  Run from the CR
root.  Safe to re-run.
"""

import json
import re
import shutil
import sys
from pathlib import Path

BS = chr(92)
BASES = {"CR_BZBase", "CR_BZBaseCockpit"}
SKIP = {"avsav.material"}  # owned by PR #241
BLOCK = re.compile(r"^material[ \t]+(\S+)(?:[ \t]*:[ \t]*(\S+))?[^{]*?\{.*?\n\}", re.S | re.M)


def safe(name):
    return re.sub(r'[<>:"/\\|?*]', "_", name)


def main():
    act = Path(sys.argv[1])
    dry = "--dry" in sys.argv
    files = sorted(Path("Materials").glob("*.material"))
    parent = {}
    for mf in files:
        for m in BLOCK.finditer(mf.read_bytes().decode("utf-8", "replace")):
            parent[m.group(1)] = m.group(2)

    def inherits(name, seen=()):
        p = parent.get(name)
        return p in BASES or (p is not None and p not in seen and inherits(p, seen + (name,)))

    used, changed = {"cr_act_neutral.dds"}, []
    for mf in files:
        if mf.name.lower() in SKIP:
            continue
        raw = mf.read_bytes().decode("utf-8")
        nl = "\r\n" if "\r\n" in raw else "\n"
        out = []
        for m in BLOCK.finditer(raw):
            name, body = m.group(1), m.group(0)
            tex = safe(name) + "_ACT.dds"
            if not inherits(name) or not (act / tex).exists():
                continue
            if re.search(r"set_texture_alias\s+ACTMap\s+\S+", body):
                new = re.sub(r"(set_texture_alias\s+ACTMap\s+)\S+", lambda a: a.group(1) + tex, body)
            else:
                aliases = list(re.finditer(r"^([ \t]*)set_texture_alias[^\r\n]*", body, re.M))
                if aliases:
                    last = aliases[-1]
                    new = body[:last.end()] + nl + last.group(1) + "set_texture_alias ACTMap " + tex + body[last.end():]
                else:
                    brace = body.index("{") + 1
                    new = body[:brace] + nl + "\tset_texture_alias ACTMap " + tex + body[brace:]
            used.add(tex)
            if new != body:
                out.append((m.start(), m.end(), new))
        if out:
            s = raw
            for a, b, new in reversed(out):
                s = s[:a] + new + s[b:]
            changed.append(mf.name)
            if not dry:
                mf.write_bytes(s.encode("utf-8"))

    lock_path = Path("Shipping/shipping.lock.json")
    lock = json.loads(lock_path.read_bytes().decode("utf-8"))
    entries = lock["files"]
    runtimes = {f["runtime"].lower() for f in entries}
    added = [t for t in sorted(used, key=str.lower) if t.lower() not in runtimes]
    if not dry:
        for tex in sorted(used, key=str.lower):
            shutil.copyfile(act / tex, Path("Assets/Textures") / tex)
        prefix = ("assets" + BS + "textures" + BS)
        for tex in added:
            e = {"source": "Assets" + BS + "Textures" + BS + tex, "runtime": tex}
            idx = [i for i, f in enumerate(entries) if f["source"].lower().startswith(prefix)]
            pos = next((i for i in idx if entries[i]["source"].lower() > e["source"].lower()), idx[-1] + 1)
            entries.insert(pos, e)
        lock["count"] = len(entries)
        lock_path.write_bytes((json.dumps(lock, indent=2, ensure_ascii=False) + "\n")
                              .replace("\n", "\r\n").encode("utf-8"))
    print(f"materials files {len(changed)}, textures {len(used)}, new lock entries {len(added)}, "
          f"count {lock['count'] if not dry else len(entries) + len(added)}")


if __name__ == "__main__":
    main()
