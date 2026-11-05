"""Opens the built window (tests/out/ForeverUIManager.exe) on a fake WoW Forever
folder and saves a picture of it per scenario, in tests/out/shots. The window
sits off screen, never takes focus and has no tray icon; the real AddOns,
settings and Run key are never touched (FUM_HOME, FUM_GAME, FUM_TEST_BIN).
The pack's list is the repository's own pack.json (FUM_PACK), read from disk.

    python -I tests/window_test.py [fresh] [install] [guides] [update] [waiting] [pulled] [find] [voice]

fresh: a new list from the pack, checked: its 12 addons, the 4 voice packs
unticked. install: what Install all would put in (the ticked ones; downloads
the real releases), the voice packs left out. guides: the Polestar guides
tab, each guide installed (needs install first). update: an addon made to
look one version old, so Auto update takes the release again. waiting: the
same with the game "open". pulled: a guide pulled by the site (a test pull)
goes. find: Find on GitHub (its result in the log). voice (not in the
default run, 150 MB): the bosses voice pack ticked, then installed.
Set FUM_NO_API=1 to ask only GitHub's pages (no API calls); the whole run
with the API spends about 50 of its 60 an hour.
Prints one line per scenario; exit code = failures.
"""
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
EXE = os.path.join(OUT, "ForeverUIManager.exe")
WORK = os.path.join(OUT, "window")
SHOTS = os.path.join(OUT, "shots")
PACK = os.path.normpath(os.path.join(HERE, "..", "..", "pack.json"))
VOICES = "rusty-key/spoken-wow"


def fake_game():
    game = os.path.join(WORK, "World of Warcraft", "_forever_")
    os.makedirs(os.path.join(game, "Interface", "AddOns"), exist_ok=True)
    open(os.path.join(game, "Wow.exe"), "wb").close()
    with open(os.path.join(game, ".flavor.info"), "w") as f:
        f.write("Product Flavor!STRING:0\nwowf\n")
    return game


def addons_folder():
    return os.path.join(fake_game(), "Interface", "AddOns")


def run(name, extra):
    env = dict(os.environ)
    env.update({
        "FUM_HOME": os.path.join(WORK, "home"),
        "FUM_GAME": fake_game(),
        "FUM_GAME_VERSION": "1.60.1",
        "FUM_TEST_BIN": os.path.join(WORK, "bin"),
        "FUM_SHOT": os.path.join(SHOTS, name + ".png"),
        "FUM_PACK": PACK,
    })
    env.update(extra)
    shot = env["FUM_SHOT"]
    if os.path.exists(shot):
        os.remove(shot)
    started = time.time()
    try:
        subprocess.run([EXE], env=env, timeout=900)
    except subprocess.TimeoutExpired:
        return False, "timed out"
    return os.path.exists(shot), "%.0f s" % (time.time() - started)


def rows():
    path = os.path.join(WORK, "home", "addons.json")
    with open(path, encoding="utf-8") as f:
        return path, json.load(f)


def key(row):
    return row["repo"] + (" " + row["series"] if row.get("series") else "")


def edit(change):
    path, data = rows()
    for row in data["addons"]:
        change(row)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)


def make_old(row):
    if row.get("repo") == "EllesmereGaming/EllesmereUI":
        row["tag"] = "v0.0.1-old"


def tick_bosses(row):
    if row.get("title") == "Spoken Bosses Audio":
        row.pop("want", None)


def bin_count():
    b = os.path.join(WORK, "bin")
    return len(os.listdir(b)) if os.path.isdir(b) else 0


def main():
    wanted = sys.argv[1:] or ["fresh", "install", "guides", "update", "waiting", "pulled", "find"]
    os.makedirs(SHOTS, exist_ok=True)
    if "fresh" in wanted and os.path.isdir(WORK):
        shutil.rmtree(WORK)
    fails = 0
    for name in wanted:
        extra = {}
        if name in ("install", "guides", "voice"):
            extra["FUM_SHOT_INSTALL"] = "1"
        if name in ("guides", "pulled", "find"):
            extra["FUM_SHOT_TAB"] = "guides"
        if name == "find":
            extra["FUM_SHOT_FIND"] = "1"
        if name in ("update", "waiting"):
            edit(make_old)
        if name == "voice":
            edit(tick_bosses)
        if name in ("fresh", "install", "voice"):
            extra["FUM_SHOT_PICK"] = "Spoken Quests Audio"
        if name == "waiting":
            extra["FUM_TEST_RUNNING"] = "1"
        if name == "pulled":
            # The first guide from polestar.guide that is installed (its list changes).
            installed = [r for r in rows()[1]["addons"] if r.get("kind") == "pack" and r.get("tag")]
            pulled_id, pulled_tag = (installed[0]["id"], installed[0]["tag"]) if installed else ("lightforge", "1.0.0")
            extra["FUM_TEST_PULL"] = pulled_id
        bins = bin_count()
        ok, took = run(name, extra)
        _, data = rows()
        repos = {key(r): r for r in data["addons"] if "repo" in r}
        packs = {r["id"]: r for r in data["addons"] if r.get("kind") == "pack"}
        addons = [r for r in repos.values() if not r.get("guide")]
        voices = [r for r in addons if r["repo"] == VOICES and "audio" in r.get("series", "")]
        ticked = [r for r in addons if r.get("want", True) and r not in voices]
        ell = repos.get("EllesmereGaming/EllesmereUI", {})
        ours = repos.get("morderous/foreverui", {})
        folders = os.listdir(addons_folder())
        pack_folders = [f for f in folders if f.startswith("PolestarPack_")]
        voice_folders = [f for f in folders if f.startswith("SpokenQuestsAudio") or f in ("SpokenReadablesAudio", "SpokenPlacesAudio", "SpokenBossesAudio")]
        note = "addons=%d installed=%d voices=%s ellesmere=%s/%s guides=%s folders=%d pack_folders=%d voice_folders=%s bin=%d" % (
            len(addons), len([r for r in addons if r.get("tag")]),
            ",".join("%s:%s%s" % (r["title"].replace("Spoken ", "").replace(" Audio", ""), "ticked" if r.get("want", True) else "unticked", "/" + r["tag"] if r.get("tag") else "") for r in voices),
            ell.get("tag"), ell.get("known"),
            ",".join("%s:%s" % (k, v.get("tag") or "pulled" if v.get("pulled") else v.get("tag")) for k, v in packs.items()),
            len(folders), len(pack_folders), ",".join(voice_folders) or "-", bin_count())
        if name == "fresh":
            ok = ok and len(addons) == 12 and len(voices) == 4 and all(r.get("want") is False and r.get("auto") is False for r in voices) \
                and not any(r.get("tag") for r in addons) and len(ticked) == 8
        if name == "install":
            # Every ticked one with a release is in; ForeverUI only once its repository has one.
            missing = [r["title"] for r in ticked if r.get("known") and r.get("tag") != r.get("known")]
            ok = ok and not missing and not voice_folders and not any(r.get("tag") for r in voices) and len(folders) >= 61
            note += " | not in: " + (",".join(missing) or "-") + " | ForeverUI: " + str(ours.get("tag") or ours.get("known") or "no release yet")
        if name == "guides":
            git = [r for r in repos.values() if r.get("guide")]
            ok = ok and len(packs) >= 1 and all(p.get("tag") for p in packs.values()) and len(git) == 4 and all(g.get("tag") for g in git) and len(pack_folders) == len(packs) + 4
        if name == "update":
            ok = ok and ell.get("tag") == ell.get("known") and bin_count() == bins + 1
        if name == "waiting":
            ok = ok and ell.get("tag") == "v0.0.1-old"
        if name == "pulled":
            lf = packs.get(pulled_id, {})
            pulled_bin = [b for b in os.listdir(os.path.join(WORK, "bin")) if "%s %s pulled" % (pulled_id, pulled_tag) in b]
            ok = ok and not lf.get("tag") and lf.get("pulled") and "PolestarPack_" + pulled_id not in folders and len(pulled_bin) == 1
            note += " | pulled " + pulled_id
        if name == "find":
            log = open(os.path.join(WORK, "home", "log.txt"), encoding="utf-8").read().splitlines()
            said = [l for l in log if "  search: " in l]
            ok = ok and bool(said)
            note += " | " + (said[-1].split("  search: ")[1] if said else "no search line")
        if name == "voice":
            bosses = [r for r in voices if r["title"] == "Spoken Bosses Audio"]
            ok = ok and bosses and bosses[0].get("tag") and voice_folders == ["SpokenBossesAudio"]
        print("%-8s %s  %s  %s" % (name, "ok" if ok else "FAIL", took, note))
        fails += 0 if ok else 1
    return fails


if __name__ == "__main__":
    sys.exit(main())
