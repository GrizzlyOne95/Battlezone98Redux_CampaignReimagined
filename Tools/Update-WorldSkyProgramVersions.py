"""Version compiled sky delegates by source hash to invalidate Ogre microcode."""
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent / "Shaders"
for filename in ("CR_skydome.program", "cr17_cloud.program"):
    path = ROOT / filename
    text = path.read_text()
    names = {}
    for match in re.finditer(r"(?:vertex|fragment)_program\s+(\S+)\s+(?:hlsl|glsl)\s*\{([^}]+)\}", text):
        old, body = match.groups()
        source = re.search(r"\bsource\s+(\S+)", body)
        if source:
            options = re.findall(r"\b(?:target|syntax|entry_point|preprocessor_defines)\s+[^\r\n]+", body)
            digest = hashlib.sha256(((ROOT / source[1]).read_text()+"\n"+"\n".join(options)).encode()).hexdigest()[:10]
            names[old] = re.sub(r"_art_[0-9a-f]{10}$", "", old) + "_art_" + digest
    text = re.sub(r"\b[A-Za-z_][A-Za-z_0-9]*\b", lambda m: names.get(m[0], m[0]), text)
    if text != path.read_text():
        path.write_text(text)
        print(path.name)
