# ForeverUI Quest Log

ForeverUI's quest log for WoW Forever (Interface 16001), written from scratch: the classic two-page quest log.

- The quest's text on the left page (on parchment) and the list of quests on the right. `/fql swap` puts the list on the left.
- The list: the quests by zone, with their level, colored by difficulty, and a tag for complete, failed, elite, dungeon, raid, group and daily quests. A check mark shows the tracked ones. The quest count is at the top.
- The page: the quest's objectives with their progress, the suggested group size, the money it needs, the description, and the rewards (the items to choose from, the items and spells it gives, money and experience). Hover a reward for its tooltip; shift-click it to link it.
- Buttons: Abandon (with our own question, which also names the quest items that go with it), Share (in a group), Track or Untrack, Close.
- Clicks in the list: click a quest to read it; shift-click to link it into an open chat line, or else to track or untrack it, as in Classic; right-click to track or untrack it. Click a zone to fold or unfold it; shift-click a zone, or "Collapse all", for every zone.
- The window moves by its title bar. The grip in the corner makes it wider or taller, and both pages grow with it, each keeping its share. Drag the bar between the pages to give one more room than the other. On a wide page the rewards take more columns. Escape closes it.

## The keys

The quest log key (L, or whatever key has "Toggle Quest Log" in Key Bindings) opens this window instead of Blizzard's quest log, which on WoW Forever is the side panel of the world map. The map key (M) is left alone, so it opens just the map. `/fql key` gives the quest log key back to Blizzard; this window then has a key of its own in Key Bindings > AddOns > ForeverUI Quest Log.

The micro menu's quest log button and a click on a quest in the objective tracker still open Blizzard's map with its quest log: taking those over would mean closing Blizzard's map from addon code, which taints it.

## Commands and options

`/fql` opens or closes it. `/fql swap`, `/fql key`, `/fql scale 1.2`, `/fql reset` (place, size, the pages' widths and scale).

With ForeverUI, `/fql options` (or the F by the minimap) opens its page in the ForeverUI options: the L key, its layer (Low, Medium, High, Dialog, or Front of all, over every other window), where it opens (where you left it, or the middle of the screen), lock, scale, width, height, background opacity, the list's side, the text page's share, Escape and sounds.

## How it stays out of Blizzard's way

Nothing of Blizzard's is replaced or hooked. The key goes to the window through an override binding on the keys of "Toggle Quest Log", to a button of its own (the way Pretty Wide Quest Log does it, MIT). The quest's text is drawn by this addon, not with Blizzard's shared QuestInfo pieces, so the map's quest details and the quest giver window never run its code. Abandoning asks with a window of its own, not with Blizzard's popup.

Install: copy the `ForeverUI_QuestLog` folder to `_forever_\Interface\AddOns` and restart the game (a new addon is only seen at start).
