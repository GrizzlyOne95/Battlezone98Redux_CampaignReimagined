#!/usr/bin/env python3
"""Static audit of the N64 Pilot Mode branches in the 22 Campaign Reimagined missions.

Run from anywhere: python3 Tools/MissionTests/Audit-PilotMode.py
Exit status is non-zero on any finding; one line per finding as file:line: [check] text.

Regions audited per mission script: the main block that starts at the comment
line containing "N64 Pilot Mode branch (" and ends at the next "-- CR pilot mode <<"
(any case), "-- CR PDA <<" or "-- N64 Pilot Mode branch end" line (misn05cr has no
end marker: the block ends at the `end` closing the last top-level function
named *Pilot*), plus every small "-- CR pilot mode >>" ... "<<" hook region.

Checks
  1 regions   every mission yields a non-empty main block.
  2 build     literal ODF names passed to Build/BuildAt/TryBuild/BuildSupply (or the
              repair/ammo pod defaults of BuildSupply) must be a buildItemN of a
              producer ODF of the mission's faction. When the builder argument is a
              variable the region ties to an ODF (IsOdf(var, "x") on a path to the
              call, or a literal producer ODF in the same function) only that
              producer is checked; otherwise ANY producer of the faction is
              accepted. buildItems come from ODF/ in the repo and, for ODFs that
              are not in the repo, from fixtures/pilot_stock_odf.json
              (python3 Audit-PilotMode.py --regen-stock-fixture, needs the local
              stock extract; CI only reads the JSON).
  3 afford    scrapCost of every pilot-built ODF must not exceed the team's max scrap
              (SetMaxScrap, default 1000), and, when the pilot queue builds no
              scavenger (no scrap income), must not exceed the starting scrap the
              mission script sets (SetScrap / SetPilot literals). A floor check, not
              an economy simulation.
  4 refs      every GetHandle("literal") in the regions must be a `label =` or
              `name =` in the mission BZN (or be given by SetLabel in the script).
              Handles that may be nil (GetHandle, GetNearest*, GetPlayerHandle,
              region functions returning a possibly-nil local, locals declared
              without a value) must be guarded before use as unit or target of
              Goto/Follow/Attack/Pickup/Dropoff/BuildAt/SetCommand: same enclosing
              function, earlier than the call, in a condition (if/elseif/while/and/
              or/not/until, e.g. alive(x), IsValid(x), `if x then`). Exempt a call
              line with `-- pilot-audit: <reason>`.
  5 orders    every Goto/Follow/Attack/Pickup/Dropoff/Retreat/Patrol/Defend/SetCommand
              call must sit in a periodically re-evaluated path (the enclosing
              function is a registered update function -- named in `update = f` or
              called *Update* -- and no enclosing `if` latches itself by assigning a
              variable its own condition tests) or carry
              `-- pilot-order: once, <why a single order is safe>` on the call line.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "Scripts"
ODF_DIR = ROOT / "ODF"
MISSIONS_DIR = ROOT / "Missions"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "pilot_stock_odf.json"
STOCK_ODF = Path(r"C:\Users\iestu\Documents\GIT\Battlezone_Source\BZ1\Redux\stock_odf")

# script -> (bzn files, faction)
MISSIONS = {
    "misn05cr": (["misn05cr"], "nsdf"), "misn06cr": (["misn06cr"], "nsdf"),
    "misn07cr": (["misn07cr"], "nsdf"), "misn08cr": (["misn08cr"], "nsdf"),
    "misn09cr": (["misn09cr"], "nsdf"), "misn10cr": (["misn10cr"], "nsdf"),
    "misn11cr": (["misn11cr"], "nsdf"), "misn12cr": (["misn12cr"], "nsdf"),
    "misn13cr": (["misn13cr"], "nsdf"), "misn14cr": (["misn14cr"], "nsdf"),
    "CRMisn15": (["misn15", "misn15b"], "nsdf"), "CRMisn16": (["misn16", "misn16b"], "nsdf"),
    "misn17cr": (["misn17cr"], "nsdf"), "misn18cr": (["misn18cr"], "nsdf"),
    "misns1cr": (["misns1cr"], "cca"), "misns2cr": (["misns2cr"], "cca"),
    "misns3cr": (["misns3cr"], "cca"), "misns4cr": (["misns4cr", "misns4"], "cca"),
    "misns5cr": (["misns5cr"], "cca"), "misns6cr": (["misns6cr", "misns6"], "cca"),
    "misns7cr": (["misns7cr"], "cca"), "misns8cr": (["misns8cr"], "cca"),
}
FACTION_PRODUCERS = {
    "nsdf": ["avrecy", "avmuf", "avslf", "avcnst"],
    "cca": ["svrecy", "svmuf", "svslf", "svcnst"],
}

ORDER_FUNCS = {"Goto", "Follow", "Attack", "Pickup", "Dropoff", "Retreat", "Patrol",
               "Defend", "SetCommand"}
# index of the argument holding the target handle (besides arg 0, the unit)
TARGET_ARG = {"Goto": 1, "Follow": 1, "Attack": 1, "Pickup": 1, "Dropoff": 1,
              "Defend": 1, "BuildAt": 2, "SetCommand": 3}
GUARDED_FUNCS = set(ORDER_FUNCS) | {"BuildAt"}
NILABLE_FUNCS = {"GetHandle", "GetPlayerHandle", "GetNearestObject", "GetNearestEnemy",
                 "GetNearestFriend", "GetNearestVehicle", "GetNearestBuilding",
                 "GetNearestPowerup", "GetTarget", "GetWhoShotMe"}
BUILD_FUNCS = {"Build", "BuildAt", "TryBuild", "BuildSupply"}

# ---------------------------------------------------------------- lexer


def lex(text):
    """Tokens as (kind, text, line); kinds id/num/str/op/cm."""
    toks = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in " \t\r":
            i += 1
        elif text.startswith("--", i):
            m = re.match(r"--\[(=*)\[", text[i:i + 40])
            if m:
                close = "]" + m.group(1) + "]"
                j = text.find(close, i)
                j = n if j < 0 else j + len(close)
                toks.append(("cm", text[i:j], line))
                line += text.count("\n", i, j)
                i = j
            else:
                j = text.find("\n", i)
                j = n if j < 0 else j
                toks.append(("cm", text[i:j], line))
                i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            toks.append(("str", text[i + 1:j], line))
            i = j + 1
        elif c == "[" and re.match(r"\[=*\[", text[i:i + 10]):
            m = re.match(r"\[(=*)\[", text[i:i + 10])
            close = "]" + m.group(1) + "]"
            j = text.find(close, i)
            j = n if j < 0 else j + len(close)
            toks.append(("str", text[i:j], line))
            line += text.count("\n", i, j)
            i = j
        elif c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_][A-Za-z_0-9]*", text[i:i + 80])
            toks.append(("id", m.group(0), line))
            i += m.end()
        elif c.isdigit():
            m = re.match(r"0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?", text[i:i + 40])
            toks.append(("num", m.group(0), line))
            i += m.end()
        else:
            m = re.match(r"\.\.\.|\.\.|==|~=|<=|>=|::|.", text[i:i + 3])
            toks.append(("op", m.group(0), line))
            i += m.end()
    return toks


# ---------------------------------------------------------------- regions

MAIN_START = re.compile(r"N64 Pilot Mode branch \(")
END_MARK = re.compile(r"--\s*(?:CR\s+(?:pilot\s+mode|PDA)\s*<<|N64 Pilot Mode branch end)", re.I)
OPEN_MARK = re.compile(r"--\s*CR\s+(?:pilot\s+mode|PDA)\s*>>", re.I)


def read_lines(path):
    return path.read_bytes().decode("utf-8", "replace").split("\n")


def find_regions(lines):
    """Return (main (start,end) 1-based inclusive or None, [hook (start,end)])."""
    main = None
    start = None
    for idx, ln in enumerate(lines):
        if start is None and MAIN_START.search(ln) and ln.lstrip().startswith("--"):
            start = idx
    if start is not None:
        end = None
        for idx in range(start + 1, len(lines)):
            if END_MARK.search(lines[idx]):
                end = idx
                break
        if end is None:  # no end marker: `end` closing the last top-level *Pilot* function
            last = None
            for idx in range(start, len(lines)):
                if re.match(r"(local )?function\s+\w*Pilot\w*", lines[idx]):
                    last = idx
            if last is not None:
                for idx in range(last + 1, len(lines)):
                    if lines[idx].rstrip("\r") == "end":
                        end = idx
                        break
        if end is not None:
            main = (start + 1, end + 1)
    hooks = []
    open_at = None
    for idx, ln in enumerate(lines):
        if OPEN_MARK.search(ln):
            open_at = idx
        elif END_MARK.search(ln) and "branch end" not in ln and open_at is not None:
            s, e = open_at + 1, idx + 1
            open_at = None
            if main and (s <= main[0] <= e or main[0] <= s <= main[1]):
                continue  # the main block's own wrapper
            hooks.append((s, e))
    return main, hooks


# ---------------------------------------------------------------- parse

KEYWORDS = {"and", "or", "not", "nil", "true", "false", "function", "if", "then", "end", "else", "elseif",
            "local", "return", "for", "while", "do", "repeat", "until", "in", "break"}
OPENERS = {"function", "if", "do", "repeat"}


def chain_at(code, i):
    """Dotted/indexed name chain starting at code[i]; returns (normalized text, end index)."""
    if code[i][0] != "id":
        return None, i
    parts = [code[i][1]]
    j = i + 1
    while j < len(code):
        t = code[j][1]
        if code[j][0] == "op" and t in (".", ":") and j + 1 < len(code) and code[j + 1][0] == "id":
            parts.append(t + code[j + 1][1])
            j += 2
        elif code[j][0] == "op" and t == "[":
            depth, k = 1, j + 1
            while k < len(code) and depth:
                if code[k][0] == "op" and code[k][1] == "[":
                    depth += 1
                elif code[k][0] == "op" and code[k][1] == "]":
                    depth -= 1
                k += 1
            parts.append("[]")
            j = k
        else:
            break
    return "".join(parts), j


class Src:
    def __init__(self, path):
        self.path = path
        self.name = path.name
        text = path.read_bytes().decode("utf-8", "replace")
        self.lines = text.split("\n")
        toks = lex(text)
        self.comments = {}
        for kind, txt, ln in toks:
            if kind == "cm":
                self.comments[ln] = self.comments.get(ln, "") + txt
        self.code = [t for t in toks if t[0] != "cm"]
        self._structure()

    def _structure(self):
        code = self.code
        self.matching = {}  # index of `(`/`{`/`[` -> index of closer
        stack = []
        for i, (kind, t, _) in enumerate(code):
            if kind == "op" and t in "({[":
                stack.append(i)
            elif kind == "op" and t in ")}]" and stack:
                self.matching[stack.pop()] = i
        # functions and blocks
        self.functions = []  # dict(name, start, end, parent)
        self.ctx = {}        # token index -> (function index, [(cond_start, cond_end, body_start)])
        st = []              # entries: dict(kind, fn, cond, body)
        fn_stack = []
        pending_while = None
        for i, (kind, t, ln) in enumerate(code):
            if kind == "id":
                if t == "while":
                    pending_while = i + 1
                elif t == "function":
                    name = None
                    if i + 1 < len(code) and code[i + 1][0] == "id":
                        name, _ = chain_at(code, i + 1)
                    elif i >= 2 and code[i - 1][1] == "=" and code[i - 2][0] == "id":
                        name, _ = chain_at(code, i - 2)
                    self.functions.append({"name": name, "start": i, "end": None,
                                           "parent": fn_stack[-1] if fn_stack else None})
                    fn_stack.append(len(self.functions) - 1)
                    st.append({"kind": "function", "fn": fn_stack[-1]})
                elif t == "if":
                    st.append({"kind": "if", "cond": (i + 1, None), "body": None})
                elif t == "elseif":
                    if st and st[-1]["kind"] == "if":
                        st[-1]["cond"] = (i + 1, None)
                        st[-1]["body"] = None
                elif t == "else":
                    if st and st[-1]["kind"] == "if":
                        st[-1]["cond"] = None
                        st[-1]["body"] = i + 1
                elif t == "then":
                    if st and st[-1]["kind"] == "if" and st[-1]["cond"] and st[-1]["cond"][1] is None:
                        st[-1]["cond"] = (st[-1]["cond"][0], i)
                        st[-1]["body"] = i + 1
                elif t == "do":
                    if pending_while is not None:
                        st.append({"kind": "while", "cond": (pending_while, i), "body": i + 1})
                        pending_while = None
                    else:
                        st.append({"kind": "do", "cond": None, "body": i + 1})
                elif t == "repeat":
                    st.append({"kind": "repeat", "cond": None, "body": i + 1})
                elif t in ("end", "until") and st:
                    ent = st.pop()
                    ent["end"] = i
                    if ent["kind"] == "function":
                        self.functions[ent["fn"]]["end"] = i
                        fn_stack.pop()
            if kind == "id" or kind == "op":
                conds = []
                for e in st:
                    if e["kind"] in ("if", "while") and e.get("cond") and e["cond"][1] is not None and e["body"] is not None:
                        conds.append({"cond": e["cond"], "body": e["body"], "ref": e})
                self.ctx[i] = (fn_stack[-1] if fn_stack else None, conds)
        for f in self.functions:
            if f["end"] is None:
                f["end"] = len(code) - 1

    def outer_fn(self, fi):
        """Nearest enclosing function that has a name (closures belong to their named parent)."""
        while fi is not None and not self.functions[fi]["name"]:
            fi = self.functions[fi]["parent"]
        return fi

    def args(self, open_idx):
        """Split call args at `(` index -> list of (start, end) token ranges (end exclusive)."""
        close = self.matching.get(open_idx)
        if close is None:
            return []
        res, depth, s = [], 0, open_idx + 1
        for i in range(open_idx + 1, close):
            kind, t, _ = self.code[i]
            if kind == "op" and t in "({[":
                depth += 1
            elif kind == "op" and t in ")}]":
                depth -= 1
            elif kind == "op" and t == "," and depth == 0:
                res.append((s, i))
                s = i + 1
        if close > open_idx + 1:
            res.append((s, close))
        return res

    def calls(self, lo_line, hi_line):
        """All calls f(...) / a.b(...) with the line of the name in [lo_line, hi_line]."""
        out = []
        code = self.code
        for i, (kind, t, ln) in enumerate(code):
            if kind != "id" or ln < lo_line or ln > hi_line:
                continue
            if i + 1 < len(code) and code[i + 1][:2] == ("op", "("):
                if i > 0 and code[i - 1][:2] == ("id", "function"):
                    continue
                # method/field chain start
                j = i
                while j >= 2 and code[j - 1][0] == "op" and code[j - 1][1] in (".", ":") and code[j - 2][0] == "id":
                    j -= 2
                full = "".join(code[k][1] for k in range(j, i + 1))
                out.append({"name": t, "full": full, "idx": i, "line": ln, "open": i + 1})
        return out

    def text(self, a, b):
        return " ".join(("\"%s\"" % x[1]) if x[0] == "str" else x[1] for x in self.code[a:b])

    def annotation(self, line, tag):
        c = self.comments.get(line, "")
        m = re.search(tag + r":\s*(\S.*)", c)
        return m.group(1).strip() if m else None

    def stmt_start_ok(self, j):
        """Index of the first token of the statement-ish window ending at token j (same line,
        extended over previous lines that end in a continuation token)."""
        code = self.code
        line = code[j][2]
        k = j
        while k > 0:
            pk = code[k - 1]
            if pk[2] == line:
                k -= 1
                continue
            if pk[1] in ("and", "or", "not", "(", ",", "==", "~=", "then") and pk[0] in ("id", "op"):
                if pk[1] == "then":
                    break
                line = pk[2]
                k -= 1
                continue
            break
        return k

    def chains_in(self, a, b):
        """Normalized name chains (and their start index) in code[a:b], skipping call names."""
        out = []
        j = a
        while j < b:
            kind, t, _ = self.code[j]
            if kind == "id" and t not in ("and", "or", "not", "nil", "true", "false", "function",
                                          "if", "then", "end", "local", "return", "else", "elseif"):
                prev = self.code[j - 1] if j > 0 else None
                if prev and prev[0] == "op" and prev[1] in (".", ":"):
                    j += 1
                    continue
                c, e = chain_at(self.code, j)
                nxt = self.code[e] if e < len(self.code) else None
                if not (nxt and nxt[:2] == ("op", "(")):
                    out.append((c, j))
                j = max(e, j + 1)
            else:
                j += 1
        return out

    def assignments(self, a, b):
        """(lhs chains list, rhs (start,end) ranges list, index of `=`) for statements in [a,b)."""
        code = self.code
        res = []
        for i in range(a, b):
            if code[i][:2] != ("op", "="):
                continue
            # LHS: walk back over chains separated by commas
            lhs, k = [], i - 1
            while k >= a:
                # find chain start by scanning back over id/./:/[ ] tokens
                e = k
                depth = 0
                while k >= a:
                    kd, t, _ = code[k]
                    if kd == "op" and t == "]":
                        depth += 1
                    elif kd == "op" and t == "[":
                        depth -= 1
                    elif depth == 0 and not ((kd == "id" and t not in KEYWORDS) or (kd == "op" and t in (".", ":"))):
                        break
                    k -= 1
                s = k + 1
                if s > e:
                    break
                c, _ = chain_at(code, s)
                if c is None:
                    break
                lhs.insert(0, c)
                if k >= a and code[k][:2] == ("op", ","):
                    k -= 1
                    continue
                break
            # RHS: to end of line, extended across open brackets; split at top-level commas
            line = code[i][2]
            j, depth, rhs, s = i + 1, 0, [], i + 1
            while j < len(code):
                kd, t, ln = code[j]
                if depth == 0 and (ln != line and not (code[j - 1][:2] in (("op", ","), ("op", "="))
                                                         or t in ("and", "or"))
                                   or (kd == "op" and t == ";")
                                   or (kd == "id" and t in ("end", "else", "elseif", "until"))):
                    break
                if kd == "op" and t in "({[":
                    depth += 1
                elif kd == "op" and t in ")}]":
                    depth -= 1
                    if depth < 0:
                        break
                elif kd == "op" and t == "," and depth == 0:
                    rhs.append((s, j))
                    s = j + 1
                j += 1
            rhs.append((s, j))
            res.append((lhs, rhs, i))
        return res


# ---------------------------------------------------------------- ODF / BZN data

ROLE_CLASS = {"recycler": "recycler", "factory": "factory", "armory": "armory",
              "constructor": "constructionrig"}
FACTION_PREFIX = {"nsdf": ("av",), "cca": ("sv", "bv", "sav")}


class OdfDb:
    """ODF facts (classLabel, scrapCost, buildItems): repo ODF/ first, then the stock fixture.
    With regen=True missing ODFs are read from the local stock extract and remembered."""

    def __init__(self, regen=False):
        self.regen = regen
        self.cache = {}
        self.recorded = {}
        self.fixture = {}
        if not regen and FIXTURE.exists():
            self.fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))

    @staticmethod
    def parse(text):
        info = {"classLabel": None, "scrapCost": None, "buildItems": []}
        items = {}
        for raw in text.splitlines():
            line = raw.split("//")[0].strip()
            m = re.match(r'(\w+)\s*=\s*"?([^"\s]*)"?', line)
            if not m:
                continue
            k, v = m.group(1), m.group(2)
            if k.lower() == "classlabel" and info["classLabel"] is None:
                info["classLabel"] = v.lower()
            elif k.lower() == "scrapcost" and info["scrapCost"] is None:
                try:
                    info["scrapCost"] = int(float(v))
                except ValueError:
                    pass
            else:
                mm = re.match(r"buildItem(\d+)$", k, re.I)
                if mm:
                    items[int(mm.group(1))] = v.lower()
        info["buildItems"] = [items[k] for k in sorted(items)]
        return info

    def get(self, name, record=True):
        """ODF info dict or None. `record` marks it as referenced for the fixture."""
        name = name.lower()
        if name in self.cache:
            info, src = self.cache[name]
        else:
            info, src = None, None
            p = ODF_DIR / (name + ".odf")
            if p.exists():
                info, src = self.parse(p.read_bytes().decode("utf-8", "replace")), "repo"
            elif name in self.fixture:
                info, src = self.fixture[name], "fixture"
            elif self.regen and (STOCK_ODF / (name + ".odf")).exists():
                info = self.parse((STOCK_ODF / (name + ".odf")).read_bytes().decode("utf-8", "replace"))
                src = "stock"
            self.cache[name] = (info, src)
        if info is not None and src == "stock" and record:
            self.recorded[name] = info
        return info

    def is_producer(self, name):
        info = self.get(name, record=False)
        return bool(info and info["buildItems"])


def bzn_data(bzns):
    """(labels lower-set, PrjID set) over the mission's BZN files; None when none exists."""
    labels, prj, found = set(), set(), False
    for b in bzns:
        p = MISSIONS_DIR / (b + ".bzn")
        if not p.exists():
            continue
        found = True
        t = p.read_bytes().decode("latin-1")
        labels.update(x.lower() for x in re.findall(r"^\s*label = (\S+)", t, re.M))
        labels.update(x.lower() for x in re.findall(r"^\s*name = (\S+)", t, re.M))
        prj.update(x.lower() for x in re.findall(r"\[GameObject\]\s*PrjID \[1\] =\s*(\S+)", t))
    return (labels, prj) if found else None


def producer_set(db, faction, prj):
    """Producer ODFs of the faction named in the BZN or the script, closed over what they can build."""
    pref = FACTION_PREFIX[faction]
    out = set()
    for n in sorted(prj):
        if n.startswith(pref) and db.is_producer(n):
            out.add(n)
    todo = list(out)
    while todo:
        n = todo.pop()
        for it in db.get(n)["buildItems"]:
            if it not in out and db.is_producer(it):
                out.add(it)
                todo.append(it)
    return out


# ---------------------------------------------------------------- checks


class Report:
    def __init__(self):
        self.findings = []
        self.summary = {}

    def add(self, src, line, check, text):
        self.findings.append("Scripts/%s:%d: [%s] %s" % (src.name, line, check, text))

    def count(self, mission, key, n=1):
        self.summary.setdefault(mission, {}).setdefault(key, 0)
        self.summary[mission][key] += n


def literal_arg(src, rng):
    a, b = rng
    if b - a == 1 and src.code[a][0] == "str":
        return src.code[a][1]
    return None


def role_of(name):
    n = name.lower().rsplit(".", 1)[-1]
    for key, role in (("rec", "recycler"), ("muf", "factory"), ("fac", "factory"),
                      ("slf", "armory"), ("armory", "armory"), ("cnst", "constructor"),
                      ("cons", "constructor")):
        if key in n:
            return role
    return None


def table_strings(src, a, b):
    """String literals directly inside the first `{ ... }` found in code[a:b]."""
    out = []
    for i in range(a, b):
        if src.code[i][:2] == ("op", "{"):
            for j in range(i, src.matching.get(i, i)):
                if src.code[j][0] == "str":
                    out.append(src.code[j][1])
            break
    return out


def build_odfs(src, call, lo_tok):
    """ODF strings a build call passes (literal args, BuildSupply defaults, loop-table items)
    as (odf, builder-arg-text) pairs; non-literals that cannot be resolved are skipped."""
    code = src.code
    name = call["name"]
    args = src.args(call["open"])
    builder_ix, odf_ixs = {"Build": (0, [1]), "BuildAt": (0, [1]), "TryBuild": (0, [1]),
                           "BuildSupply": (1, [2, 3])}[name]
    if builder_ix >= len(args):
        return []
    btxt = src.text(*args[builder_ix])
    res = []
    for k in odf_ixs:
        if k < len(args):
            lit = literal_arg(src, args[k])
            if lit is not None:
                res.append((lit, btxt))
                continue
            # X[n] where X is the loop variable of `for _, X in ipairs({ { .. }, .. })`
            a, b = args[k]
            ch, _ = chain_at(code, a) if code[a][0] == "id" else (None, a)
            mm = re.match(r"(\w+)\[\](?!.)", ch or "")
            if mm:
                idx = None
                for t in range(a, b):
                    if code[t][:2] == ("op", "[") and code[t + 1][0] == "num":
                        idx = int(code[t + 1][1])
                for j in range(call["idx"], lo_tok, -1):
                    if code[j][1] == "for":
                        e = j
                        while e < len(code) and code[e][1] != "do":
                            e += 1
                        hdr = [t[1] for t in code[j:e]]
                        if mm.group(1) in hdr and "ipairs" in hdr and idx:
                            res.extend((x, btxt) for x in strs_by_col(src, j, e, idx))
                            break
        elif name == "BuildSupply":  # defaults of CRPilotBranch.BuildSupply
            res.append((("aprepa", "apammo")[k - 2], btxt))
    return res


def split_commas(src, a, b):
    """Top-level comma-separated ranges of code[a:b]."""
    res, depth, st = [], 0, a
    for k in range(a, b):
        kd, t, _ = src.code[k]
        if kd == "op" and t in "({[":
            depth += 1
        elif kd == "op" and t in ")}]":
            depth -= 1
        elif kd == "op" and t == "," and depth == 0:
            res.append((st, k))
            st = k + 1
    if st < b:
        res.append((st, b))
    return res


def strs_by_col(src, a, b, col):
    """Strings at position `col` (1-based) of each `{ x, y }` row of the first table in code[a:b]."""
    out = []
    for i in range(a, b):
        if src.code[i][:2] == ("op", "{"):
            for row in split_commas(src, i + 1, src.matching.get(i, i)):
                if src.code[row[0]][:2] == ("op", "{"):
                    cells = split_commas(src, row[0] + 1, src.matching.get(row[0], row[0]))
                    if col - 1 < len(cells):
                        lit = literal_arg(src, cells[col - 1])
                        if lit is not None:
                            out.append(lit)
            break
    return out


def start_scrap(src, consts):
    """(max literal start scrap for team 1 or None, max literal SetMaxScrap or None)."""
    start, cap = None, None
    for c in src.calls(0, 10 ** 9):
        if c["name"] not in ("SetScrap", "AddScrap", "SetMaxScrap"):
            continue
        args = src.args(c["open"])
        if len(args) < 2:
            continue
        team = src.text(*args[0]).strip()
        team = consts.get(team, team)
        if str(team) != "1":
            continue
        val = literal_arg(src, args[1]) if False else None
        a, b = args[1]
        if b - a == 1 and src.code[a][0] == "num":
            val = float(src.code[a][1])
        elif b - a == 1 and src.code[a][0] == "id" and src.code[a][1] in consts:
            val = float(consts[src.code[a][1]])
        if val is None:
            continue
        if c["name"] == "SetMaxScrap":
            cap = max(cap or 0, val)
        else:
            start = max(start or 0, val)
    return start, cap


def top_consts(src):
    out = {}
    code = src.code
    for i in range(len(code) - 3):
        if (code[i][:2] == ("id", "local") and code[i + 1][0] == "id" and code[i + 2][:2] == ("op", "=")
                and code[i + 3][0] == "num"):
            out[code[i + 1][1]] = code[i + 3][1]
    return out


def nilable_analysis(src, lo, hi, region_fns):
    """Set of normalized chains that may hold nil because of a lookup."""
    code = src.code
    nilable = set()
    nil_fns = set()
    for f in src.functions:
        if f["name"] and lo <= f["start"] <= hi:
            body = range(f["start"], f["end"])
            has_lookup = any(code[i][1] in NILABLE_FUNCS or code[i][1] in ("AllObjects", "AllCraft")
                             for i in body if code[i][0] == "id")
            has_ret = any(code[i][:2] == ("id", "return") and code[i + 1][1] not in ("end",)
                          for i in body)
            if has_lookup and has_ret:
                nil_fns.add(f["name"].rsplit(".", 1)[-1].rsplit(":", 1)[-1])
    sources = NILABLE_FUNCS | nil_fns

    def operand_nilable(a, b):
        # split at top-level and/or
        parts, depth, s = [], 0, a
        for i in range(a, b):
            kd, t, _ = code[i]
            if kd == "op" and t in "({[":
                depth += 1
            elif kd == "op" and t in ")}]":
                depth -= 1
            elif depth == 0 and kd == "id" and t in ("and", "or"):
                parts.append((s, i))
                s = i + 1
        parts.append((s, b))
        for pa, pb in parts:
            if pa >= pb:
                continue
            if code[pa][0] == "id":
                ch, e = chain_at(code, pa)
                if e < pb and code[e][:2] == ("op", "("):
                    if ch.rsplit(".", 1)[-1].rsplit(":", 1)[-1] in sources and src.matching.get(e) == pb - 1:
                        return True
                elif e == pb and ch in nilable:
                    return True
            elif code[pa][:2] == ("op", "{"):
                for i in range(pa, pb):
                    if code[i][0] == "id" and code[i][1] in sources and code[i + 1][:2] == ("op", "("):
                        return "container"
        return False

    for _ in range(3):  # propagate through plain copies
        for lhs, rhs, _ in src.assignments(lo, hi):
            for n, c in enumerate(lhs):
                if n < len(rhs):
                    r = operand_nilable(*rhs[n])
                    if r:
                        nilable.add(c)
                        if r == "container":
                            nilable.add(c + "[]")
    # `local a, b` without a value
    for i in range(lo, hi):
        if code[i][:2] == ("id", "local") and code[i + 1][0] == "id" and code[i + 1][1] != "function":
            j = i + 1
            names = []
            while j < hi and code[j][0] == "id":
                names.append(code[j][1])
                if code[j + 1][:2] == ("op", ","):
                    j += 2
                else:
                    j += 1
                    break
            if j < hi and code[j][:2] != ("op", "=") and code[j][2] != code[i][2] or \
               (j < hi and code[j][2] == code[i][2] and code[j][:2] not in (("op", "="),)
                    and code[j][1] in ("end", ";")):
                nilable.update(names)
    return nilable, sources


def is_guarded(src, chain, upto, fn_start):
    code = src.code
    j = fn_start
    while j < upto:
        kd, t, _ = code[j]
        if kd == "id":
            prev = code[j - 1] if j > 0 else None
            if prev and prev[0] == "op" and prev[1] in (".", ":"):
                j += 1
                continue
            c, e = chain_at(code, j)
            if c == chain:
                nxt = code[e] if e < len(code) else None
                if nxt and nxt[:2] != ("op", "=") or not nxt:
                    if nxt and nxt[1] in ("~=", "==") :
                        return True
                    s = src.stmt_start_ok(j)
                    for k in range(s, j):
                        if code[k][0] == "id" and code[k][1] in ("if", "elseif", "while", "until", "and",
                                                                 "or", "not", "assert"):
                            return True
                j = max(e, j + 1)
                continue
        j += 1
    return False


def check_refs(src, mission, regions, bzn, report, nilable, sources):
    code = src.code
    labels = bzn[0] if bzn else set()
    # labels set by the script itself
    runtime = set()
    for c in src.calls(0, 10 ** 9):
        if c["name"] == "SetLabel":
            for a in src.args(c["open"]):
                v = literal_arg(src, a)
                if v:
                    runtime.add(v.lower())
    strvars = {}
    for lo, hi in regions:
        for lhs, rhs, i in src.assignments(*tok_range(src, lo, hi)):
            for n, ch in enumerate(lhs):
                if n < len(rhs) and rhs[n][1] - rhs[n][0] == 1 and code[rhs[n][0]][0] == "str":
                    strvars.setdefault(ch, set()).add(code[rhs[n][0]][1])
    # fields in table constructors: NAME = "str"
    for lo, hi in regions:
        a, b = tok_range(src, lo, hi)
        for i in range(a, b - 2):
            if code[i][0] == "id" and code[i + 1][:2] == ("op", "=") and code[i + 2][0] == "str":
                strvars.setdefault("." + code[i][1], set()).add(code[i + 2][1])
    tables = {}
    for lo, hi in regions:
        a, b = tok_range(src, lo, hi)
        for i in range(a, b - 3):
            if code[i][0] == "id" and code[i + 1][:2] == ("op", "=") and code[i + 2][:2] == ("op", "{"):
                close = src.matching.get(i + 2, i + 2)
                tables.setdefault(code[i][1], []).extend(
                    code[r[0]][1] for r in split_commas(src, i + 3, close)
                    if r[1] - r[0] == 1 and code[r[0]][0] == "str")
    for lo, hi in regions:
        a, b = tok_range(src, lo, hi)
        for c in src.calls(lo, hi):
            if c["name"] != "GetHandle":
                continue
            args = src.args(c["open"])
            if not args:
                continue
            names = None
            lit = literal_arg(src, args[0])
            if lit is not None:
                names = [lit]
            else:
                x, y = args[0]
                if code[x][0] == "id":
                    ch, e = chain_at(code, x)
                    if e == y:
                        names = sorted(strvars.get(ch, []) or strvars.get("." + ch.rsplit(".", 1)[-1], []))
                        if not names:  # loop variable over a literal table
                            for j in range(c["idx"], a, -1):
                                if code[j][1] == "for":
                                    e2 = j
                                    while e2 < len(code) and code[e2][1] != "do":
                                        e2 += 1
                                    hdr = [t[1] for t in code[j:e2]]
                                    if ch in hdr and "ipairs" in hdr:
                                        k = hdr.index("ipairs")
                                        tbl, _ = chain_at(code, j + k + 2) if code[j + k + 2][0] == "id" else (None, 0)
                                        if tbl:
                                            names = tables.get(tbl.rsplit(".", 1)[-1], [])
                                        break
            if not names:
                report.count(mission, "refs-dynamic")
                continue
            exempt = src.annotation(c["line"], "pilot-audit")
            for nm in names:
                report.count(mission, "refs")
                if bzn is None:
                    continue
                if nm.lower() not in labels and nm.lower() not in runtime and not exempt:
                    report.add(src, c["line"], "refs", 'GetHandle("%s") is not a label/name in %s.bzn '
                               "nor set by SetLabel" % (nm, "/".join(MISSIONS[mission][0])))


def tok_range(src, lo_line, hi_line):
    a = next((i for i, t in enumerate(src.code) if t[2] >= lo_line), len(src.code))
    b = next((i for i, t in enumerate(src.code) if t[2] > hi_line), len(src.code))
    return a, b


def check_guards(src, mission, regions, report, nilable, sources):
    code = src.code
    for lo, hi in regions:
        a, b = tok_range(src, lo, hi)
        for c in src.calls(lo, hi):
            if c["name"] not in GUARDED_FUNCS:
                continue
            args = src.args(c["open"])
            idxs = [0]
            if c["name"] in TARGET_ARG and TARGET_ARG[c["name"]] < len(args):
                idxs.append(TARGET_ARG[c["name"]])
            exempt = src.annotation(c["line"], "pilot-audit")
            fi = src.ctx[c["idx"]][0]
            ofn = src.outer_fn(fi)
            fstart = src.functions[ofn]["start"] if ofn is not None else a
            for ix in idxs:
                if ix >= len(args):
                    continue
                x, y = args[ix]
                if x >= y or code[x][0] != "id":
                    continue
                ch, e = chain_at(code, x)
                direct = (e < y and code[e][:2] == ("op", "(")
                          and ch.rsplit(".", 1)[-1].rsplit(":", 1)[-1] in sources and src.matching.get(e) == y - 1)
                report.count(mission, "nil-checked")
                if exempt:
                    continue
                if direct:
                    report.add(src, c["line"], "nil", "%s(...) argument %d is a lookup call used unguarded"
                               % (c["name"], ix + 1))
                elif e == y and ch in nilable and not is_guarded(src, ch, c["idx"], fstart):
                    report.add(src, c["line"], "nil", "%s argument %d '%s' comes from a lookup that can return nil "
                               "and is not guarded (alive/IsValid/if) before this call" % (c["name"], ix + 1, ch))


def latched(src, c):
    """True when an enclosing if/while condition is cleared or set by its own body (a one-shot latch).
    Assignments of a time value (`now`, GetTime) are timer re-arms, not latches."""
    code = src.code
    for ent in src.ctx[c["idx"]][1]:
        ca, cb = ent["cond"]
        cond_chains = {ch for ch, _ in src.chains_in(ca, cb)}
        end = ent["ref"].get("end", len(code))
        for lhs, rhs, i in src.assignments(ent["body"], end):
            for n, ch in enumerate(lhs):
                if ch in cond_chains:
                    r = rhs[n] if n < len(rhs) else rhs[-1]
                    toks = [t[1] for t in code[r[0]:r[1]]]
                    if "now" in toks or "GetTime" in toks:
                        continue
                    return True
    return False


def periodic_functions(src, lo, hi):
    names = set()
    for f in src.functions:
        if f["name"] and lo <= f["start"] <= hi and f["name"].rsplit(".", 1)[-1].rsplit(":", 1)[-1] == "Update":
            names.add(f["name"])
        if f["name"] and lo <= f["start"] <= hi and f["name"].endswith("PilotUpdate"):
            names.add(f["name"])
    code = src.code
    for i in range(lo, hi - 2):
        if code[i][:2] == ("id", "update") and code[i + 1][:2] == ("op", "=") and code[i + 2][0] == "id":
            c, _ = chain_at(code, i + 2)
            names.add(c)
    # called every update from a periodic function, from an unlatched call site
    changed = True
    while changed:
        changed = False
        for f in src.functions:
            if f["name"] in names:
                continue
            if not f["name"] or not (lo <= f["start"] <= hi):
                continue
            short = f["name"].rsplit(".", 1)[-1].rsplit(":", 1)[-1]
            for i in range(lo, hi):
                if code[i][0] == "id" and code[i][1] == short and i + 1 < len(code) \
                        and code[i + 1][:2] == ("op", "(") and not (i > 0 and code[i - 1][:2] == ("id", "function")):
                    fi = src.ctx.get(i, (None, []))[0]
                    of = src.outer_fn(fi)
                    if of is not None and src.functions[of]["name"] in names \
                            and not latched(src, {"idx": i}):
                        names.add(f["name"])
                        changed = True
                        break
    return names


def check_orders(src, mission, regions, report, periodic):
    for lo, hi in regions:
        for c in src.calls(lo, hi):
            if c["name"] not in ORDER_FUNCS:
                continue
            fi = src.ctx[c["idx"]][0]
            ofn = src.outer_fn(fi)
            fname = src.functions[ofn]["name"] if ofn is not None else None
            note = src.annotation(c["line"], "pilot-order")
            if note is not None:
                if not note.lower().startswith("once"):
                    report.add(src, c["line"], "order", "pilot-order annotation must start with 'once, <why>'")
                elif not re.match(r"once,\s*\S", note, re.I):
                    report.add(src, c["line"], "order", "pilot-order annotation needs a reason: 'once, <why>'")
                report.count(mission, "orders-annotated")
                continue
            if fname in periodic and not latched(src, c):
                report.count(mission, "orders-periodic")
                continue
            why = "latched by its own condition" if fname in periodic else "runs in %s, not a per-update path" % (fname or "<top level>")
            report.add(src, c["line"], "order", "%s is a one-shot order (%s); re-send it periodically or add "
                       "'-- pilot-order: once, <why a single order is safe>'" % (c["name"], why))


def check_builds(src, mission, regions, report, db, faction, prod_all, consts):
    code = src.code
    per_role = {}
    for role, cls in ROLE_CLASS.items():
        per_role[role] = {p for p in prod_all if (db.get(p, record=False) or {}).get("classLabel") == cls}
    built = []  # (line, odf) in source order
    for lo, hi in regions:
        a, b = tok_range(src, lo, hi)
        for c in src.calls(lo, hi):
            if c["name"] not in BUILD_FUNCS:
                continue
            exempt = src.annotation(c["line"], "pilot-audit")
            for odf, btxt in build_odfs(src, c, a):
                report.count(mission, "builds")
                odf = odf.lower()
                role = role_of(btxt)
                cands = per_role.get(role) or prod_all if role else prod_all
                cands = cands or prod_all
                built.append((c["line"], odf))
                if exempt:
                    continue
                if not cands:
                    report.add(src, c["line"], "build", "no %s producer ODF resolved for the mission" % faction)
                    continue
                ok = any(odf in (db.get(p, record=False) or {"buildItems": []})["buildItems"] for p in cands)
                if ok:
                    db.get(odf)  # remember for the stock fixture
                    continue
                where = "%s producer%s (%s)" % (role or faction, "" if role is None or len(cands) == 1 else "s",
                                                 ", ".join(sorted(cands)))
                report.add(src, c["line"], "build", '"%s" (builder %s) is not a buildItem of %s' % (odf, btxt, where))
    # affordability
    start, cap = start_scrap(src, consts)
    seen, total, has_scav = set(), 0, False
    infos = []
    for line, odf in built:
        info = db.get(odf)
        if info is None:
            if db.fixture is not None and not db.regen:
                report.add(src, line, "afford", 'ODF "%s" is in neither ODF/ nor fixtures/pilot_stock_odf.json '
                           "(run --regen-stock-fixture)" % odf)
            continue
        infos.append((line, odf, info))
        if info.get("classLabel") == "scavenger":
            has_scav = True
    for line, odf, info in infos:
        cost = info.get("scrapCost")
        if cost is None:
            continue
        if cap is not None and cost > cap:
            report.add(src, line, "afford", '"%s" costs %d scrap, above the team max scrap %d' % (odf, cost, cap))
        elif start is not None and not has_scav and cost > start:
            report.add(src, line, "afford", '"%s" costs %d scrap but the mission starts with %d and the pilot '
                       "queue builds no scavenger" % (odf, cost, start))
        if odf not in seen:
            seen.add(odf)
            total += cost
    report.summary.setdefault(mission, {})["queue-cost"] = total
    report.summary[mission]["start-scrap"] = start
    report.summary[mission]["scav-in-queue"] = has_scav


# ---------------------------------------------------------------- main


def audit(db):
    report = Report()
    for mission in MISSIONS:
        bzns, faction = MISSIONS[mission]
        path = SCRIPTS / (mission + ".lua")
        if not path.exists():
            report.findings.append("Scripts/%s.lua:1: [regions] script is missing" % mission)
            continue
        src = Src(path)
        main, hooks = find_regions(src.lines)
        if main is None or main[1] - main[0] < 5:
            report.findings.append("Scripts/%s.lua:1: [regions] no non-empty Pilot Mode main block found "
                                   "(start marker 'N64 Pilot Mode branch (' / end marker)" % mission)
            continue
        report.summary[mission] = {"region-lines": main[1] - main[0] + 1 + sum(h[1] - h[0] + 1 for h in hooks)}
        regions = [main] + hooks
        bzn = bzn_data(bzns)
        if bzn is None:
            report.findings.append("Missions/%s.bzn:1: [refs] no BZN found for %s" % (bzns[0], mission))
        prj = set(bzn[1]) if bzn else set()
        prj.update(t[1].lower() for t in src.code if t[0] == "str" and re.fullmatch(r"[A-Za-z0-9_]{4,8}", t[1]))
        prod_all = producer_set(db, faction, prj)
        if not prod_all:  # BZN has none: any producer ODF of the faction known to the repo
            for p in sorted(ODF_DIR.glob("*.odf")):
                n = p.stem.lower()
                if n.startswith(FACTION_PREFIX[faction]) and db.is_producer(n):
                    prod_all.add(n)
        consts = top_consts(src)
        mlo, mhi = tok_range(src, main[0], main[1])
        nilable, sources = nilable_analysis(src, mlo, mhi, None)
        for lo, hi in hooks:
            a, b = tok_range(src, lo, hi)
            n2, s2 = nilable_analysis(src, a, b, None)
            nilable |= n2
            sources |= s2
        check_builds(src, mission, regions, report, db, faction, prod_all, consts)
        check_refs(src, mission, regions, bzn, report, nilable, sources)
        check_guards(src, mission, regions, report, nilable, sources)
        periodic = periodic_functions(src, mlo, mhi)
        check_orders(src, mission, regions, report, periodic)
    return report


def regen_fixture():
    if not STOCK_ODF.exists():
        print("stock ODF extract not found: %s" % STOCK_ODF)
        return 2
    db = OdfDb(regen=True)
    audit(db)
    # referenced producers in the BZNs were looked up with record=False; record those that are
    # stock-only producers of a faction so CI can resolve them
    for mission, (bzns, faction) in MISSIONS.items():
        bzn = bzn_data(bzns)
        if bzn:
            for n in producer_set(db, faction, bzn[1]):
                db.get(n)
    out = {k: db.recorded[k] for k in sorted(db.recorded)}
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print("wrote %s (%d stock-only ODFs: %s)" % (FIXTURE.relative_to(ROOT), len(out), ", ".join(out)))
    return 0


def main():
    if "--regen-stock-fixture" in sys.argv:
        return regen_fixture()
    report = audit(OdfDb())
    for mission, s in report.summary.items():
        print("%-9s lines=%-3s builds=%-2s refs=%-2s(+%s dynamic) nil-checked=%-2s orders: %s periodic, %s annotated | "
              "queue cost %s, start scrap %s, scav %s" % (
                  mission, s.get("region-lines"), s.get("builds", 0), s.get("refs", 0), s.get("refs-dynamic", 0),
                  s.get("nil-checked", 0), s.get("orders-periodic", 0), s.get("orders-annotated", 0),
                  s.get("queue-cost"), s.get("start-scrap"), s.get("scav-in-queue")))
    for f in report.findings:
        print(f)
    print("%d finding(s)" % len(report.findings))
    return 1 if report.findings else 0


if __name__ == "__main__":
    sys.exit(main())
