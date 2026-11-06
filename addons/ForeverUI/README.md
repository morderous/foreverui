# ForeverUI

Installs the ForeverUI look in WoW Forever (Interface 16001), and holds the pack's options and its minimap button.

## Options and the minimap button

A flat square with an F in your class color (round on the minimap's edge). Click: a menu of the pack, beside the mouse: the trainer (with how many spells to train now), the quest log, Move UI and the options. Right click: the options. With EllesmereUI Minimap on, it goes in EllesmereUI's list of addon buttons, which opens under the mouse with the others; EllesmereUI's minimap options show, hide and size it there. Without it (or by the General page's choice, after a reload), it sits on the minimap's edge: drag it, and it slides round the edge after the mouse, on a round minimap or a square one. The addon compartment by the minimap and `/fui options` open the options too.

**Move UI**, at the bottom of the options' sidebar (or `/fui move`, or the F's menu), in the way of the game's Edit Mode: a grid over the screen, and what has no other way to move (the XP bar, the trainer's level-up notice) as it is, outlined in the class color with its name on a tag. Drag it; let go near a line of the grid or the middle of the screen and it snaps to it. Right click it: back to its place. "Reset all", and "Done" (or Escape), which brings the options back. The windows (the quest log, the trainer) move by their title bars at any time, so they are not in it. Each addon brings its own boxes, through the global `ForeverUI_Movers`.

In the game's AddOns list, ForeverUI and ForeverUI XPbar have icons of our own (`Media/Icon.tga`, drawn by `tools/make_icons.py`).

The options window has a page per addon of the pack, each with "Reset this page":

- **General**: the minimap button (in EllesmereUI's list or a square of its own; for its own square, on or off, size and back to its place; its color) and "Install the look".
- **XP bar**: everything about ForeverUI XPbar: width, bar height, scale, text sizes and outline, lock, layer, top or bottom of the screen, each of its words, the colors of the bar's parts, Blizzard's bar, and a new XP per hour session.
- **Quest log**: everything about ForeverUI Quest Log: the L key, its layer (up to in front of everything), where it opens (where you left it or the middle of the screen), lock, scale, width, height, background opacity, the list's side, the text page's share, Escape and sounds.
- **Trainer**: everything about ForeverUI Trainer: how many levels ahead, spells that need a talent, the weapons you know and the ones your class can't use, the level-up chat line and notice, the window's layer, scale, opacity, lock and Escape, the spell book's drag, and its minimap button and the count on it.
- **Modules**: the pack's addons, which are installed and which are on. ForeverUI XPbar, Quest Log and Trainer turn on and off here, for every character, from the next reload ("Reload now"); EllesmereUI, OpenMap, Polestar and the extras show their state, with what is left out without the required ones. Every part of ForeverUI checks for them before it uses them, so a missing one only leaves its part out.
- **Map**: the map's layer (the game's, Medium, High, Dialog, or in front of everything) and where its window opens (where you left it, or the middle of the screen every time). The layer goes on the map frame each time it opens. Its title, close and full-screen buttons stay one layer over the map, as the game has them, so they keep working in every layer; in front of everything, the map takes the layer under the top one, so the tooltips stay over it.
  - **With OpenMap**: these are what OpenMap has no setting for, with a button to OpenMap's own options. The middle goes in as OpenMap's saved place, so OpenMap keeps it there. Nothing in OpenMap's folder changes.
  - **Without OpenMap** (`MapWindow.lua`), the game's map window gets what OpenMap would give it: drag its title bar to move it; drag either bottom corner to make it bigger or smaller (it keeps its shape, from 50% to 200%, or the size slider); right click the title bar to put it back in its place, a corner for its size. And a flat look, as the rest of the pack: the gold frame, portrait and grey bars give way to a dark flat window with a 1px edge, the buttons inside its title row; the map, its bar of places and its buttons stay the game's. Each of these turns off on the page. The window moves and sizes through a secure handler of the game's, out of combat, right after the game places it: no code of the map's own runs ours, so its pins keep working in combat. In combat it opens where the game puts it and goes back after. The full-screen map stays the game's. With Move Any, or EllesmereUI's Shifter on, the window is theirs to place; with EllesmereUI's window skin, the look is theirs.

An addon brings its own page by adding an entry to the global `ForeverUI_Pages` (see the top of `Options.lua`); the options draw it with their kit.

## The look

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
