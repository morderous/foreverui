# ForeverUI XPbar

ForeverUI's XP bar for WoW Forever (Interface 16001), written from scratch.

- Above the bar: time played, time at this level, and the XP of the quests that are complete and only wait to be turned in, as a share of the level.
- The bar: XP in blue, completed quest XP in yellow after it, rested XP in faint blue after that. Level, XP and percent on it.
- Below the bar: time to level at this session's XP per hour, and rested XP.
- Uses EllesmereUI's font when EllesmereUI is on.
- Time played is asked once per load and kept out of the chat window; typing /played still shows it there.
- The XP per hour session survives a reload or a relog within 10 minutes.
- Hides Blizzard's XP and reputation bars when they are still shown (EllesmereUI Action Bars off, or its "Use Blizzard data bars" on), the way EllesmereUI does it. Not in combat (it waits), and not at max level. `/fxp blizzard` keeps them (back after a /reload).

Shift + drag moves it. `/fxp scale 1.2`, `/fxp width 700`, `/fxp lock`, `/fxp unlock`, `/fxp reset`, `/fxp session`, `/fxp blizzard`.

With ForeverUI, `/fxp options` (or the F by the minimap) opens its page in the ForeverUI options, with every setting: show or hide it, width, bar height, scale, the two text sizes and the outline, lock, layer, top or bottom of the screen, each of its words (time played, completed quests, level, XP numbers (whole or short, as 4.1k / 10.1k), percent, time to level, rested, the tooltip), the completed quests and rested parts of the bar and the colors of XP, completed quests, rested and the background, Blizzard's bar, and a new XP per hour session.

Install: copy the `ForeverUI_XPBar` folder to `_forever_\Interface\AddOns` and restart the game (a new addon is only seen at start).
