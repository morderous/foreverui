# ForeverUI Trainer

ForeverUI's trainer window for WoW Forever (Interface 16001): what your class trainer has for you, and where.

- **Spells.** What you can train now, with what it all costs (in red when you are short), what needs another spell first, and the spells of the next levels, level by level, each with what it costs. Every line has the spell's icon, name, rank, level and price. Hover a spell for its tooltip; shift-click it to link it in the chat.
- **The trainer.** On top, the nearest class trainer and where it stands (zone and coordinates), from Polestar. Without Polestar, the last class trainer you visited. "Map pin" puts the game's pin and arrow on it.
- **Weapon masters.** The weapon masters of your faction's capitals, each with a map pin and the weapons they teach your class: which ones you know, the level each one needs (Polearms from 20) and its price.
- **Level up.** At each level with something new at the trainer, a line in the chat and a notice on the screen: how many spells, what they cost in all, and where. A click on the notice opens the window.
- **In the spell book.** A Trainer tab, a square with the book beside the spell book's own tabs (General and the specs): it lays the list over the book's pages, under its tabs, until you pick another tab, use the search box or close the book. With the book's two pages open, Spells is on the left page and Weapon masters on the right, as the quest log's two pages; with one page, the two are behind tabs. With EllesmereUI it has the pack's dark look; without it, as if it were the book's own: its parchment, its ink, its fonts, its divider under each heading, and the game's buttons. Only the tab, its ground and the list are ours; nothing of the book is hidden or changed.
- **Opening it.** ForeverUI's F has it in its menu, with how many spells there are to train now. A minimap button of its own (the book, with that count in its corner) is an option, off at the start: it goes where ForeverUI puts the F, in EllesmereUI Minimap's list of addon buttons or on the minimap's edge. Click: the window. Right click: its options.
- **Move UI.** ForeverUI's Move UI moves the level-up notice (the window moves by its title bar).
- **The spell book moves.** Drag Blizzard's spell book by its top bar, as ForeverUI's quest log moves, and it opens where you left it. It is never moved with plain addon code: every move goes through one of the game's secure handlers, out of combat, so the spells cast from the book are not tainted. In combat it opens where the game puts it, and goes back once the combat ends. With EllesmereUI's Shifter on (EllesmereUI's QoL options), the Shifter moves it instead and this stands aside.

The window moves by its title bar, and the grip in its corner sizes it. Escape closes it.

## Where the list comes from

- The spells of every class by level, their base prices, the rank or spell each one needs, and the weapon masters come from [What's Training?](https://github.com/fusionpit/WhatsTraining) 11.2.0 by Sveng (MIT License: `LICENSE-WhatsTraining.txt`). `tools/make_trainer_data.py` writes them into `Data.lua`.
- Each visit to a class trainer reads its whole list (the filters that hide some services are turned on for the read and back after) and keeps it for your class, race and faction: the real prices, with your reputation's discount, and any spell the data lacks. A visit to a weapon master keeps its prices too.
- The spell book's future spells (the grey "learned at level N" ones) fill in what neither has.
- The nearest trainer is Polestar's, read while the game runs. Nothing of Polestar's is copied, and every call to it is checked first.

## Commands and options

`/ftr` opens or closes it. `/ftr weapons`, `/ftr notice` (shows the level-up notice), `/ftr info` (what it knows: the data, the trainers seen, the spell book's future spells), `/ftr reset` (place, size and scale). A key of its own is in Key Bindings > AddOns > ForeverUI Trainer, with none set at the start.

With ForeverUI, `/ftr options` (or a right click on its minimap button) opens its page in the ForeverUI options: how many levels ahead, spells that need a talent, the weapons you know and the ones your class can't use, the chat line and the notice, the window's layer, scale, opacity, lock and Escape, the spell book's tab and drag (and "Back to its place"), and its own minimap button and its count.

Install: copy the `ForeverUI_Trainer` folder to `_forever_\Interface\AddOns` and restart the game (a new addon is only seen at start).
