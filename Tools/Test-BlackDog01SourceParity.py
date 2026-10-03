"""Audit source preservation and mission identifier coverage; run from repo root."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "References/BlackDog01Source/BlackDog01Mission.cpp").read_bytes()
lua = (ROOT / "Scripts/bd01.lua").read_text(encoding="utf-8")

# Reconstitute upstream CRLF bytes to verify the ORIGINAL Git blob hash.
# Every declaration, native serialization byte of text, and comment is covered.
raw = source.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
blob = b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw
assert hashlib.sha1(blob).hexdigest() == "c55ead909f5e1c4415c7fe43d6d14115ff9e2dc4", "source archive changed"

cpp = source.decode("utf-8")
code = re.sub(r"--\[\[.*?\]\]|--[^\n]*", "", lua, flags=re.S)
cpp_code = re.sub(r"/\*.*?\*/|//[^\n]*", "", cpp, flags=re.S)
source_strings = set(re.findall(r'"([^"\n]+)"', cpp_code))
lua_strings = {s.lower() for s in re.findall(r'"([^"\n]+)"', code)}
# Include every gameplay label/path/ODF/OTF/WAV/DES, omitting C++ includes,
# serializer field names and the macro's filename suffix pseudo-literal.
ignored = {"b_array", "f_array", "h_array", "i_array", ".WAV"}
identifiers = {s.lower() for s in source_strings if s not in ignored and not s.endswith(".h")}
assert identifiers <= lua_strings, f"missing source identifiers: {sorted(identifiers - lua_strings)}"
assert '"bd01002.wav"' in code.lower(), "blocking macro audio missing"
assert '--SucceedMission(GetTime(), "bd01win.des");' in lua, "disabled debug win call missing"
assert not re.search(r"\bObjectiveObjects\s*\(|\bgoto\b|::\w+::", code), "unsupported Lua API/syntax"
assert '"cvfigh"' in code and '"cvltnk"' in code and '"apcamr"' in code
print(f"BlackDog01 source parity: archive hash and {len(identifiers)} mission identifiers passed")
