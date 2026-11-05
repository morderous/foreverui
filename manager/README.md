# ForeverUI Manager

A small Windows app that keeps your WoW Forever addons up to date, straight from their authors' GitHub releases, and installs Polestar's community guides.

No middle man: no account, no addon site, no service of ours in between. The app asks GitHub (and, for guides, polestar.guide) itself, checks each download against the sha256 its source gives, and puts the folders in `_forever_\Interface\AddOns`.

## What it does

- Finds WoW Forever by itself (Battle.net's `World of Warcraft\_forever_`, marked `wowf`), or you pick its folder.
- **Addons** holds the [ForeverUI pack](../README.md#packjson): the list in `pack.json` on this repository's `main`, read from GitHub every 6 hours and when you click **Check now**, and kept for when GitHub does not answer. Before the app has ever read it, the list starts with [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI) and [Polestar](https://github.com/fitzforge/polestar). Each addon of the pack is offered once: one you take off the list stays off, except the required ones, which cannot be taken off.
- Each addon not installed yet has a box: ticked, **Install all** puts it in (with one yes for all of them, which lists them and their sizes). The pack's extras come ticked, except the big ones (Spoken's voice packs, 2.6 GB together), which come unticked and do not update by themselves until you switch their Auto update on. **Add from GitHub...** takes any other addon's link.
- One repository can ship several addons: Spoken and each of its voice packs come from `rusty-key/spoken-wow`, each with its own series of releases. The app reads pages of releases until it finds the series, one call for all five.
- Picks the zip made for WoW Forever: the `release.json` that addon packagers put beside their zips says which one (flavor `forever`, Interface 1.6x); without it, the release's only zip, or the one named for the repository. For a repository that ships several things (Polestar's library, tools and data have releases of their own), only the addon's releases count.
- Checks a download against GitHub's sha256 and, when the release has one, the author's own `SHA256SUMS`.
- **Polestar guides** lists the community guides on [polestar.guide](https://polestar.guide), from its guide list, trusted only with its ed25519 signature from Polestar's own keys. A guide's zip must hold only what Polestar's guide compiler makes, the folders its entry names and nothing else; a folder of that name that is not the guide's is never touched. A guide the site pulls goes to the Recycle Bin.
- The same tab lists Polestar guides published on GitHub: a few looked at beforehand ([Lodestar](https://github.com/petllama/lodestar-guides), [MittenQuest](https://github.com/petllama/mittenquest-guides) and [free RestedXP](https://github.com/petllama/rxp-free-guides) conversions, [Every Quest](https://github.com/bmagic/every-quest), [Aurum's Night Elf Druid](https://github.com/AurumTitanos/Aurums-Night-Elf-Druid-Guide)), any you add by link, and any **Find on GitHub** turns up. A GitHub guide's zip must hold PolestarPack_ folders and nothing else; the window says whether it holds only what Polestar's compiler makes or code of its own. Test versions (pre-releases) are taken only for a guide that has nothing else, and only with your yes.
- Checks when it opens and every 30 minutes, from the tray (polestar.guide every 6 hours).
- **Auto update**: on by default for each addon (a new release goes in with the game closed, or as soon as you close it); off by default for guides, which update by themselves only a day after a version is out and only while it is still the same guide, publisher and folders.
- Without GitHub's API (its limit of 60 an hour used up), it asks GitHub's web pages instead: git's own list of tags for a series, and a release's list of files and sha256s.
- A big download that stops is taken up where it stopped, at once and at the next try. Before a download, and again before unpacking, it checks that the drives have room for it.
- Replaced and uninstalled folders go to the Recycle Bin. Your settings (in `WTF`) are never touched.
- Polestar's recording program (uploading what Polestar Recorder writes) is not part of this app: that is Polestar's own client's.
- One exe of about 140 KB, built with the C# compiler that comes with Windows. It is not signed, so Windows or an antivirus may warn about it the first time: check it against the `SHA256SUMS` of its release.

## Build

```
build.bat
```

## Where it keeps its things

`%APPDATA%\ForeverUIManager`: `addons.json` (your list), `settings.ini`, `log.txt`, `pack.json` (the ForeverUI pack's list last read, for offline), and `packs\` (the last guide list taken, for offline). A download that stopped waits in `%TEMP%\ForeverUIManager` for the next try (a week at most).

## Tests

`tests\run_tests.sh` builds and runs `tests\Tests.cs`: offline checks (RFC 8032's ed25519 tests among them), then, with `live`, a look at GitHub and polestar.guide; `index <dir>` checks a downloaded guide list and signature, `zip <file> <folders>` installs a real release zip, `release <dir>` checks a ForeverUI release made by `tools/make_release.py` as the app reads it. `tests\window_test.py` opens the window on a test folder, with the repository's own `pack.json`, and saves a picture of each scenario (with `FUM_NO_API=1` it asks only GitHub's pages; with the API, a whole run spends about 50 of its 60 calls an hour). None of them touches your real AddOns, settings or the Windows Run key.
