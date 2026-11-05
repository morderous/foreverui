# ForeverUI

Installs the ForeverUI look in WoW Forever (Interface 16001).

On the first login after the pack brings a new profile, a window lists what it can install, each part ticked:

- **EllesmereUI profile**: almost the whole UI (bars, unit frames, nameplates, chat, minimap, bags, quest tracker, fonts, colors). It goes in as a new EllesmereUI profile named ForeverUI, through EllesmereUI's own installer API, and keeps your UI scale. Your own profiles stay in EllesmereUI's list.
- **Edit Mode layout**: a new account layout named ForeverUI, made the active one.
- **Interface settings**: the game options the author changed (no graphics, sound or network settings, no UI scale).
- **OpenMap settings** and **Polestar settings**: options only, never map favorites, notes or drawings, or character data.
- **ForeverUI XPbar** place and size.

A part whose addon is not installed shows greyed out. Install, then the UI reloads.

- `/fui` opens the window again.
- `/fui undo` puts back what the install changed (interface settings, OpenMap, Polestar and XPbar settings, the EllesmereUI profile and the Edit Mode layout that were active), then reloads.

## For the author: capturing the look

1. Set the UI up in the game.
2. `/fui capture`, then `/reload`. The game writes the capture into `WTF\Account\<account>\SavedVariables\ForeverUI.lua`.
3. `python -I tools/make_profile.py` makes `Profile.lua` here and the review files in `profiles/`.

A capture also marks this look as installed on the author's own client, so the window does not open there.
