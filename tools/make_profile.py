"""Turns a /fui capture into the ForeverUI pack's profile.

In the game: /fui capture, then /reload (the game writes the capture into
WTF\\Account\\<account>\\SavedVariables\\ForeverUI.lua). Then:

    python -I tools/make_profile.py [path to ForeverUI.lua] [--out <folder>]

(--out writes into another folder laid out like this repository; for tests.)

Writes, in this repository:
  addons/ForeverUI/Profile.lua       the data the ForeverUI addon installs
  profiles/EllesmereUI/ForeverUI.txt the EllesmereUI export string
  profiles/EditMode/ForeverUI.txt    the Edit Mode layout string, when there is one
  profiles/cvars.txt                 the interface settings, one per line, to review
and prints a short summary.
"""
import glob
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_WTF = r"C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account"


# --- a small reader for the game's saved variables ------------------------
class Reader:
    TOKEN = re.compile(r"""
        (?P<space>\s+|--[^\n]*)
      | (?P<string>"(?:\\.|[^"\\])*")
      | (?P<number>-?(?:\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?|inf\b|nan\b))
      | (?P<word>[A-Za-z_][A-Za-z_0-9]*)
      | (?P<punct>[{}\[\]=,;])
    """, re.X)

    def __init__(self, text):
        self.tokens = []
        pos = 0
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m:
                raise ValueError("cannot read the saved variables at character %d" % pos)
            pos = m.end()
            if m.lastgroup != "space":
                self.tokens.append((m.lastgroup, m.group()))
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError("expected %r, found %r" % (value, tok[1]))
        self.i += 1
        return tok

    def value(self):
        kind, text = self.take()
        if kind == "string":
            return unescape(text[1:-1])
        if kind == "number":
            if text in ("inf", "-inf", "nan"):
                return float(text)
            return int(text) if re.fullmatch(r"-?\d+", text) else float(text)
        if kind == "word":
            return {"true": True, "false": False, "nil": None}[text]
        if text == "{":
            return self.table()
        raise ValueError("unexpected %r" % text)

    def table(self):
        out, n = {}, 0
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                out[key] = self.value()
            else:
                n += 1
                out[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return out

    def assignments(self):
        found = {}
        while self.peek()[0] is not None:
            kind, name = self.take()
            if kind != "word":
                raise ValueError("expected a variable name, found %r" % name)
            self.take("=")
            found[name] = self.value()
        return found


ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\n": "\n"}


def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = s[i + 1]
        if nxt.isdigit():
            digits = re.match(r"\d{1,3}", s[i + 1:]).group()
            out.append(chr(int(digits)))
            i += 1 + len(digits)
        else:
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
    return "".join(out)


# --- writing it back as Lua, sorted, so a new capture diffs well ----------
def lua_string(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def lua_value(v, depth):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v != v or v in (float("inf"), float("-inf")):
            raise ValueError("a number the game cannot read back: %r" % v)
        return repr(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        pad = "\t" * (depth + 1)
        keys = sorted(v, key=lambda k: (0, k, "") if isinstance(k, (int, float)) and not isinstance(k, bool) else (1, 0, str(k)))
        lines = ["{"]
        for k in keys:
            key = "[%s]" % (repr(k) if isinstance(k, (int, float)) else lua_string(str(k)))
            lines.append("%s%s = %s," % (pad, key, lua_value(v[k], depth + 1)))
        lines.append("\t" * depth + "}")
        return "\n".join(lines)
    raise ValueError("cannot write %r" % type(v))


def find_saved(arg):
    if arg:
        return arg
    found = glob.glob(os.path.join(GAME_WTF, "*", "SavedVariables", "ForeverUI.lua"))
    if not found:
        sys.exit("No ForeverUI.lua under %s. Capture in the game first (/fui capture, then /reload)." % GAME_WTF)
    return max(found, key=os.path.getmtime)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # latin-1 both ways: the game's strings are bytes (UTF-8 text and \ddd
    # escapes alike), and this way every byte comes back out as it went in.
    with open(path, "w", encoding="latin-1", newline="\n") as f:
        f.write(text)


def main():
    global ROOT
    args = sys.argv[1:]
    if "--out" in args:
        at = args.index("--out")
        ROOT = os.path.abspath(args[at + 1])
        del args[at:at + 2]
    saved = find_saved(args[0] if args else "")
    with open(saved, encoding="latin-1") as f:
        data = Reader(f.read()).assignments()
    p = data.get("ForeverUICapture")
    if not isinstance(p, dict) or not isinstance(p.get("captured"), int):
        sys.exit("%s has no capture. In the game: /fui capture, then /reload." % saved)

    when = time.strftime("%Y-%m-%d %H:%M", time.localtime(p["captured"]))
    write(os.path.join(ROOT, "addons", "ForeverUI", "Profile.lua"),
          "-- Made by tools/make_profile.py from a /fui capture of %s (game %s). Do not edit by hand.\n"
          "ForeverUI_Profile = %s\n" % (when, p.get("build", "?"), lua_value(p, 0)))

    said = ["capture of %s, game %s" % (when, p.get("build", "?"))]
    e = p.get("ellesmere")
    if isinstance(e, dict) and e.get("string"):
        write(os.path.join(ROOT, "profiles", "EllesmereUI", "ForeverUI.txt"), e["string"] + "\n")
        said.append("EllesmereUI profile %r (EllesmereUI %s): %d characters" % (e.get("from"), e.get("version"), len(e["string"])))
    em = p.get("editmode")
    if isinstance(em, dict) and em.get("string"):
        write(os.path.join(ROOT, "profiles", "EditMode", "ForeverUI.txt"), em["string"] + "\n")
        said.append("Edit Mode layout %r: %d characters" % (em.get("name"), len(em["string"])))
    elif isinstance(em, dict) and em.get("preset"):
        said.append("Edit Mode: preset layout %d" % em["preset"])
    cv = p.get("cvars") or {}
    write(os.path.join(ROOT, "profiles", "cvars.txt"),
          "".join("%s = %s\n" % (k, cv[k]) for k in sorted(cv, key=str.lower)))
    said.append("%d interface settings (profiles/cvars.txt)" % len(cv))
    for key in ("openmap", "polestar", "xpbar"):
        t = p.get(key)
        if isinstance(t, dict):
            said.append("%s: %s" % (key, ", ".join(sorted(str(k) for k in t))))
    print("\n".join(said))


if __name__ == "__main__":
    main()
