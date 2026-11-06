"""Builds addons/ForeverUI_Trainer/Data.lua from What's Training?'s data.

  python -I tools/make_trainer_data.py "<...>/_forever_/Interface/AddOns/WhatsTraining"

What's Training? (Sveng, MIT License: addons/ForeverUI_Trainer/LICENSE-WhatsTraining.txt)
keeps, for every class of WoW Forever (Classes/Camelot/<Class>.lua), the
spells its trainer teaches by level, with their price, the rank before them,
the talent, race or faction they need, and the ranks that replace each other.
This reads those files (as text, nothing of them runs) and writes the same
facts in our own shape. The weapon masters below are the ones What's Training?
lists for Forever (Classes/WeaponSkills.lua, Era's, with Woo Ping moved by
Classes/Camelot/WeaponSkills.lua).

Run it again when What's Training? brings new data; the addon itself also
learns every price and every new spell at the trainer.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "addons", "ForeverUI_Trainer", "Data.lua")
CLASSES = ("Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior")

# Weapon skills (their spell IDs) in What's Training?'s order, and the classes
# that can learn each in Forever (Era's, plus Classes/Camelot/WeaponSkills.lua:
# Rogues one-handed axes, Shamans two-handed axes and maces).
WEAPONS = [
    (196, "One-Handed Axes", "WARRIOR PALADIN HUNTER SHAMAN ROGUE", None, None),
    (197, "Two-Handed Axes", "WARRIOR PALADIN HUNTER SHAMAN", None, None),
    (198, "One-Handed Maces", "WARRIOR PALADIN ROGUE PRIEST SHAMAN DRUID", None, None),
    (199, "Two-Handed Maces", "WARRIOR PALADIN DRUID SHAMAN", None, None),
    (201, "One-Handed Swords", "WARRIOR PALADIN HUNTER ROGUE MAGE WARLOCK", None, None),
    (202, "Two-Handed Swords", "WARRIOR PALADIN HUNTER", None, None),
    (1180, "Daggers", "WARRIOR HUNTER ROGUE PRIEST SHAMAN DRUID WARLOCK MAGE", None, None),
    (15590, "Fist Weapons", "WARRIOR HUNTER ROGUE SHAMAN DRUID", None, None),
    (227, "Staves", "WARRIOR HUNTER PRIEST SHAMAN DRUID WARLOCK MAGE", None, None),
    (200, "Polearms", "WARRIOR PALADIN HUNTER DRUID", 20, 10000),
    (264, "Bows", "WARRIOR HUNTER ROGUE", None, None),
    (266, "Guns", "WARRIOR HUNTER ROGUE", None, None),
    (5011, "Crossbows", "WARRIOR HUNTER ROGUE", None, None),
    (2567, "Thrown", "WARRIOR HUNTER ROGUE", None, None),
]

# The weapon masters: npc, English name, faction, the capital's uiMapID, x, y
# and the weapon skills they teach.
MASTERS = [
    (11865, "Buliwyf Stonehand", "Alliance", 1455, 61.2, 89.5, (196, 197, 198, 199, 266, 15590)),
    (13084, "Bixi Wobblebonk", "Alliance", 1455, 62.2, 89.6, (1180, 2567, 5011)),
    (11867, "Woo Ping", "Alliance", 1453, 63.9, 69.1, (200, 201, 202, 227, 1180, 5011)),
    (11866, "Ilyenia Moonfire", "Alliance", 1457, 57.7, 46.0, (227, 264, 1180, 2567, 15590)),
    (2704, "Hanashi", "Horde", 1454, 81.5, 19.6, (196, 197, 227, 264, 2567)),
    (11868, "Sayoc", "Horde", 1454, 81.7, 19.6, (196, 197, 227, 264, 1180, 2567, 15590)),
    (11869, "Ansekhwa", "Horde", 1456, 40.0, 63.1, (198, 199, 227, 266)),
    (11870, "Archibald", "Horde", 1458, 57.3, 32.8, (200, 201, 202, 1180, 5011)),
]


# ---------------------------------------------------------------------------
# A small reader for the Lua tables of those files
# ---------------------------------------------------------------------------
TOKEN = re.compile(r'\s*(?:(--[^\n]*)|(\d+(?:\.\d+)?)|("(?:[^"\\]|\\.)*")|([A-Za-z_]\w*)|(.))', re.S)


def tokens(text):
    out = []
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            break
        pos = m.end()
        comment, number, string, name, other = m.groups()
        if comment is not None:
            continue
        if number is not None:
            out.append(("num", float(number) if "." in number else int(number)))
        elif string is not None:
            out.append(("str", string[1:-1]))
        elif name is not None:
            out.append(("name", name))
        elif other is not None and not other.isspace():
            out.append(("op", other))
    return out


class Reader:
    def __init__(self, toks, names):
        self.t = toks
        self.i = 0
        self.names = names

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else ("eof", None)

    def take(self, kind=None, value=None):
        tok = self.peek()
        if (kind and tok[0] != kind) or (value is not None and tok[1] != value):
            raise SystemExit("unexpected %r, wanted %s %s" % (tok, kind, value))
        self.i += 1
        return tok

    def value(self):
        kind, v = self.peek()
        if kind == "op" and v == "{":
            return self.table()
        if kind == "op" and v == "-":
            self.take()
            return -self.take("num")[1]
        if kind in ("num", "str"):
            self.take()
            return v
        if kind == "name":
            self.take()
            if v in ("true", "false"):
                return v == "true"
            if v == "nil":
                return None
            if v not in self.names:
                raise SystemExit("unknown name in a table: %s" % v)
            return self.names[v]
        raise SystemExit("unexpected %r" % (self.peek(),))

    def table(self):
        self.take("op", "{")
        array, keyed = [], {}
        while not (self.peek() == ("op", "}")):
            if self.peek() == ("op", "["):
                self.take()
                key = self.value()
                self.take("op", "]")
                self.take("op", "=")
                keyed[key] = self.value()
            elif self.peek()[0] == "name" and self.peek(1) == ("op", "="):
                key = self.take()[1]
                self.take()
                keyed[key] = self.value()
            else:
                array.append(self.value())
            if self.peek()[0] == "op" and self.peek()[1] in (",", ";"):
                self.take()
        self.take("op", "}")
        if keyed and array:
            raise SystemExit("a table with both kinds of keys")
        return keyed if keyed else array


def read_class(path):
    text = open(path, encoding="utf-8").read()
    toks = tokens(text)
    names, found = {}, {}
    r = Reader(toks, names)
    while r.peek()[0] != "eof":
        tok = r.peek()
        # local name = { ... }
        if tok == ("name", "local") and r.peek(1)[0] == "name" and r.peek(2) == ("op", "=") and r.peek(3) == ("op", "{"):
            r.take()
            name = r.take()[1]
            r.take()
            names[name] = r.table()
            continue
        # class.<field> = { ... }
        if tok == ("name", "class") and r.peek(1) == ("op", ".") and r.peek(2)[0] == "name" and r.peek(3) == ("op", "="):
            r.take()
            r.take()
            field = r.take()[1]
            r.take()
            if r.peek() == ("op", "{"):
                found[field] = r.table()
                continue
        r.i += 1
    m = re.search(r'wt\.forClass\("([A-Z]+)"\)', text)
    if not m:
        raise SystemExit("no class in %s" % path)
    return m.group(1), found


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------
SPELL_KEYS = {"id", "cost", "requiredIds", "requiredTalentId", "race", "faction", "skills"}


def lua_spell(s):
    unknown = set(s) - SPELL_KEYS
    if unknown:
        raise SystemExit("a spell with keys this script does not know: %s" % sorted(unknown))
    parts = ["%d, %d" % (s["id"], s.get("cost", 0))]
    if s.get("requiredIds"):
        parts.append("req = { %s }" % ", ".join(str(x) for x in s["requiredIds"]))
    if s.get("requiredTalentId"):
        parts.append("talent = %d" % s["requiredTalentId"])
    if s.get("race"):
        parts.append("race = %d" % s["race"])
    if s.get("faction"):
        if s["faction"] not in ("Alliance", "Horde"):
            raise SystemExit("faction %r" % s["faction"])
        parts.append('faction = "%s"' % s["faction"])
    if s.get("skills"):
        # a skill line at a level (the Rogue's Poisons): { skill line, level }
        if len(s["skills"]) != 1 or set(s["skills"][0]) != {"skill", "level"}:
            raise SystemExit("skills %r" % s["skills"])
        parts.append("skill = { %d, %d }" % (s["skills"][0]["skill"], s["skills"][0]["level"]))
    return "{ %s }" % ", ".join(parts)


def main(args):
    if len(args) != 1:
        sys.exit(__doc__)
    wt = args[0]
    toc = open(os.path.join(wt, "WhatsTraining.toc"), encoding="utf-8").read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    lines = [
        "-- ForeverUI Trainer's data. Written by tools/make_trainer_data.py; do not",
        "-- edit by hand, run the script again.",
        "--",
        "-- The facts come from What's Training? %s by Sveng (Classes/Camelot/*.lua" % version,
        "-- and Classes/WeaponSkills.lua), MIT License, Copyright (c) 2019: the",
        "-- notice and the license are in LICENSE-WhatsTraining.txt, beside this file.",
        "",
        "local _, T = ...",
        "",
        'T.SOURCE = "What\'s Training? %s"' % version,
        "",
        "-- [class] = { [level] = { { spellID, base cost in copper, req = { the spells",
        "-- needed first }, talent = the talent needed, race = raceID, faction = ...,",
        "-- skill = { skill line, its level } } } }",
        "T.SPELLS = {",
    ]
    ranks = {}
    total = 0
    for name in CLASSES:
        token, data = read_class(os.path.join(wt, "Classes", "Camelot", name + ".lua"))
        levels = data.get("spellsByLevel")
        if not levels:
            raise SystemExit("no spellsByLevel in %s" % name)
        lines.append("    %s = {" % token)
        for level in sorted(levels):
            spells = levels[level]
            lines.append("        [%d] = {" % level)
            for s in spells:
                lines.append("            %s," % lua_spell(s))
                total += 1
            lines.append("        },")
        lines.append("    },")
        if data.get("overriddenGroups"):
            ranks[token] = data["overriddenGroups"]
    lines += [
        "}",
        "",
        "-- The ranks of one spell, lowest first, where knowing a later one counts",
        "-- for the earlier ones too.",
        "T.RANKS = {",
    ]
    for token in sorted(ranks):
        lines.append("    %s = {" % token)
        for group in ranks[token]:
            lines.append("        { %s }," % ", ".join(str(x) for x in group))
        lines.append("    },")
    lines += [
        "}",
        "",
        "-- Weapon skills in the order they show: spellID, English name, the classes",
        "-- that can learn it, the level it needs (1 when nil) and its base cost",
        "-- (10 silver when nil).",
        "T.WEAPONS = {",
    ]
    for wid, wname, classes, level, cost in WEAPONS:
        cls = ", ".join("%s = true" % c for c in classes.split())
        extra = ""
        if level:
            extra += ", level = %d" % level
        if cost:
            extra += ", cost = %d" % cost
        lines.append('    { id = %d, name = "%s", classes = { %s }%s },' % (wid, wname, cls, extra))
    lines += [
        "}",
        "",
        "-- The weapon masters of the capitals: npc, English name, faction, the",
        "-- capital's uiMapID, x and y on it (0 to 100), and what they teach.",
        "T.MASTERS = {",
    ]
    for npc, mname, faction, umap, x, y, teaches in MASTERS:
        lines.append('    { npc = %d, name = "%s", faction = "%s", map = %d, x = %.1f, y = %.1f, teaches = { %s } },'
                     % (npc, mname, faction, umap, x, y, ", ".join(str(t) for t in teaches)))
    lines += ["}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("Data.lua: %d spells, %d classes with ranks, %d weapons, %d masters (%s)"
          % (total, len(ranks), len(WEAPONS), len(MASTERS), version))


if __name__ == "__main__":
    main(sys.argv[1:])
