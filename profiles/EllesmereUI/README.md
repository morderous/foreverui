# EllesmereUI profile

`ForeverUI.txt` is the EllesmereUI export string of the ForeverUI look, made by `tools/make_profile.py` from a `/fui capture` (see `addons/ForeverUI/README.md`). It is here to review and diff; the ForeverUI addon carries the same string in its `Profile.lua` and installs it through EllesmereUI's own installer API (`EllesmereUI.ImportProfileSilent`), keeping each player's UI scale. Nothing writes EllesmereUI's saved files directly.

The string can also be imported by hand: EllesmereUI's options, Global Settings > Profiles > Import.
