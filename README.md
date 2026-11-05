# ForeverUI

A UI package for WoW Forever: our own addons, an EllesmereUI profile, and ForeverUI Manager, the small Windows app that installs all of it and keeps it up to date, straight from GitHub.

## What is here

- `manager/`: ForeverUI Manager, the Windows app (C#, built with `manager\build.bat`). It installs and updates addons from their authors' own GitHub releases and Polestar's guides.
- `addons/ForeverUI/`: installs the ForeverUI look (the EllesmereUI profile, the Edit Mode layout, interface settings, OpenMap, Polestar and XPbar settings) from a window on first login, and captures it from the author's UI (`/fui capture`).
- `addons/ForeverUI_XPBar/`: ForeverUI XPbar, an XP bar that also shows the XP of completed quests, rested XP, XP per hour and time played.
- `profiles/`: the captured look, to review and diff: the EllesmereUI export string, the Edit Mode layout string, the interface settings.
- `tools/make_profile.py`: turns a `/fui capture` into `addons/ForeverUI/Profile.lua` and the files in `profiles/`.
- `tools/make_release.py`: builds a release into `dist/` (see [RELEASING.md](RELEASING.md)).
- `pack.json`: the pack's list, which ForeverUI Manager reads from here.

## What it needs

These are not shipped here. ForeverUI Manager installs them from their authors' own GitHub releases. `pack.json` is the list it reads, from this repository's `main`: the required ones, then the extras, which can be left out or taken off. Most extras come ticked; the big ones come unticked.

- Required: [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI), [OpenMap](https://github.com/openmap-world/openmap), [Polestar](https://github.com/fitzforge/polestar).
- Extras: [Forever Quest Tint](https://github.com/alexdia25/forever-quest-tint), [What's Training?](https://github.com/fusionpit/WhatsTraining), [Dialogue UI](https://github.com/Peterodox/YUI-Dialogue), [Spoken](https://github.com/rusty-key/spoken-wow).
- Unticked extras: the English voice packs for [Spoken](https://github.com/rusty-key/spoken-wow/releases) (quests, about 1.5 GB; readables, 475 MB; places, 456 MB; bosses, 157 MB). Spoken needs them to speak, but together they are about 2.6 GB.
- Polestar guides: [Lodestar](https://github.com/petllama/lodestar-guides), [MittenQuest](https://github.com/petllama/mittenquest-guides), [Free RestedXP](https://github.com/petllama/rxp-free-guides), [Every Quest](https://github.com/bmagic/every-quest).

No fonts are shipped here: the profile uses the fonts that come with EllesmereUI.

### pack.json

Each entry in `addons` has:

- `repo`: the GitHub repository, as `owner/name`.
- `title`: the name the manager shows.
- `required`: `true` for the ones the look needs. They cannot be taken off.
- `ticked`: for an extra, whether its box starts ticked. Left out, it is `true`. The Spoken voice packs have `false`, so nobody downloads 2.6 GB without asking for it; an unticked one also starts with Auto update off.
- `series` and `zip`, for a repository that ships several things: a regular expression for the tags of this one's releases, and the name of its zip, with `*` for any text. One repository can have several entries, one per series: Spoken and its four voice packs all come from `rusty-key/spoken-wow`.

`guides` lists the Polestar guides the same way, by `repo` and `title` (and `betas`: `true` for one that has only test versions).

The manager reads `pack.json` every 6 hours and when **Check now** is clicked. Each entry is offered once: one taken off a list stays off, except a required one. An entry the pack drops stays on people's lists, no longer required.

## Status

Work in progress. Nothing is released yet. [RELEASING.md](RELEASING.md) has the steps of a release.
