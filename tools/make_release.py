"""Builds a ForeverUI release into dist/v<version>/, ready to upload; sends nothing.

    python -I tools/make_release.py [<version>] [--no-look | --empty-profile]

The version defaults to the one in addons/ForeverUI/ForeverUI.toc. A release
needs the captured look in addons/ForeverUI/Profile.lua (tools/make_profile.py);
--no-look makes a real release of the addons alone, before the look is
captured (the look comes with a later version; ForeverUI then shows no install
window), and leaves the mark ADDONS-ONLY in dist/v<version>/ for
foreverui_publish.py. --empty-profile builds one without it, for a test only.
It makes:
  ForeverUI-<version>.zip   the ForeverUI, ForeverUI_XPBar, ForeverUI_QuestLog and ForeverUI_Trainer folders
  release.json              which zip is for WoW Forever (flavor "forever", Interface 16001),
                            as addon packagers write it, so ForeverUI Manager and other
                            managers pick the zip
  ForeverUIManager.exe      built from manager/ with manager/build.bat (never over an exe in use)
  SHA256SUMS                the sha256 of the zip and of the exe
Prints a short summary; exits with an error when a check fails."""
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDONS = os.path.join(ROOT, "addons")
FOLDERS = ("ForeverUI", "ForeverUI_XPBar", "ForeverUI_QuestLog", "ForeverUI_Trainer")
INTERFACE = 16001
# Never shipped: fonts (the profile uses EllesmereUI's), programs, and leftovers.
REFUSED = (".ttf", ".otf", ".exe", ".dll", ".bat", ".cmd", ".ps1", ".py", ".pyc", ".zip")
LEFT_OUT = ("Thumbs.db", ".DS_Store", "desktop.ini")


def toc(folder):
    path = os.path.join(ADDONS, folder, folder + ".toc")
    with open(path, encoding="utf-8-sig") as f:
        return dict(re.findall(r"^##\s*([\w-]+)\s*:\s*(.*?)\s*$", f.read(), re.M))


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def files_of(folder):
    out = []
    for root, dirs, names in os.walk(os.path.join(ADDONS, folder)):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "__pycache__")
        for name in sorted(names):
            if name in LEFT_OUT:
                continue
            if name.lower().endswith(REFUSED):
                sys.exit("not shipped: %s" % os.path.relpath(os.path.join(root, name), ADDONS))
            out.append(os.path.join(root, name))
    return out


def manager_version():
    with open(os.path.join(ROOT, "manager", "ForeverUIManager.cs"), encoding="utf-8") as f:
        source = f.read()
    version = re.search(r'public const string Version = "([\d.]+)";', source).group(1)
    assembly = re.search(r'AssemblyFileVersion\("([\d.]+)"\)', source).group(1)
    if assembly != version + ".0":
        sys.exit("the manager says %s and its exe %s" % (version, assembly))
    return version


def file_version(exe):
    out = subprocess.run(["powershell", "-NoProfile", "-Command", "(Get-Item -LiteralPath '%s').VersionInfo.FileVersion" % exe],
                         capture_output=True, text=True)
    return out.stdout.strip()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    no_look = "--no-look" in sys.argv[1:]
    empty_ok = no_look or "--empty-profile" in sys.argv[1:]
    tocs = dict((folder, toc(folder)) for folder in FOLDERS)
    version = args[0] if args else tocs["ForeverUI"]["Version"]
    with open(os.path.join(ADDONS, "ForeverUI", "Profile.lua"), encoding="utf-8") as f:
        empty = re.search(r"^ForeverUI_Profile\s*=\s*nil\s*$", f.read(), re.M) is not None
    if empty and not empty_ok:
        sys.exit("Profile.lua has no profile yet: /fui capture in the game, then tools/make_profile.py (or --no-look for the addons alone, --empty-profile for a test)")
    if not re.match(r"^\d+\.\d+\.\d+$", version):
        sys.exit("a version is three numbers: %s" % version)
    if tocs["ForeverUI"]["Version"] != version:
        sys.exit("ForeverUI.toc says %s, not %s" % (tocs["ForeverUI"]["Version"], version))
    for folder, fields in tocs.items():
        if fields.get("Interface") != str(INTERFACE):
            sys.exit("%s.toc is for Interface %s, not %d" % (folder, fields.get("Interface"), INTERFACE))

    out = os.path.join(ROOT, "dist", "v" + version)
    os.makedirs(out, exist_ok=True)
    mark = os.path.join(out, "ADDONS-ONLY")
    if no_look and empty:
        with open(mark, "w") as f:
            f.write("a release of the addons alone, without the look\n")
    elif os.path.exists(mark):
        os.remove(mark)
    zip_name = "ForeverUI-%s.zip" % version
    zip_path = os.path.join(out, zip_name)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for folder in FOLDERS:
            for path in files_of(folder):
                z.write(path, os.path.relpath(path, ADDONS).replace(os.sep, "/"))
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        bad = z.testzip()
    tops = sorted(set(n.split("/")[0] for n in names))
    if bad or tops != sorted(FOLDERS) or any("\\" in n for n in names):
        sys.exit("the zip is not right: %s %s" % (bad, tops))
    if "Profile.lua" not in [n.split("/")[-1] for n in names if n.startswith("ForeverUI/")]:
        sys.exit("ForeverUI/Profile.lua is missing")

    release = {"releases": [{"name": "ForeverUI", "version": version, "filename": zip_name, "nolib": False,
                             "metadata": [{"flavor": "forever", "interface": INTERFACE}]}]}
    with open(os.path.join(out, "release.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(release, f, indent=2)
        f.write("\n")

    exe = os.path.join(out, "ForeverUIManager.exe")
    if os.path.exists(exe):
        os.remove(exe)
    built = subprocess.run(["cmd", "/c", os.path.join(ROOT, "manager", "build.bat"), exe], capture_output=True, text=True)
    if built.returncode or not os.path.exists(exe):
        sys.exit("the manager did not build: " + (built.stdout + built.stderr).strip())
    wanted = manager_version()
    if file_version(exe) != wanted + ".0":
        sys.exit("the exe is version %s, not %s" % (file_version(exe), wanted))

    with open(os.path.join(out, "SHA256SUMS"), "w", encoding="utf-8", newline="\n") as f:
        for name in (zip_name, "ForeverUIManager.exe"):
            f.write("%s  %s\n" % (sha(os.path.join(out, name)), name))

    print("v%s in %s" % (version, os.path.relpath(out, ROOT)))
    print("  %s: %d files, %d bytes (%s)" % (zip_name, len(names), os.path.getsize(zip_path),
                                            ", ".join("%s %s" % (f, tocs[f]["Version"]) for f in FOLDERS)))
    print("  ForeverUIManager.exe: %s, %d bytes" % (wanted, os.path.getsize(exe)))
    print("  release.json, SHA256SUMS" + (", ADDONS-ONLY (no look: not uploaded)" if no_look and empty else (" (a test: no look)" if empty else "")))


if __name__ == "__main__":
    main()
