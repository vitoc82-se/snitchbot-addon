# Snitchbot addon

The in-game half of [Snitchbot](https://forever.snitchbot.app) for WoW Forever.

One window with six tabs. Open it with the minimap button (or `/sb`); it stays open over reloads until you close it, and remembers where you put it.

- **Raid**: what to bring for raid night, how many you have in bags and bank, what's missing. **New list** pastes the code from **Raid list** on [auction.snitchbot.app](https://auction.snitchbot.app) (**Copy for the addon**). **Check buffs** lists who in your group has no flask, no elixir or no food, and how many have world buffs.
- **Craft**: level a profession to 300, or to the goal you type in the **Goal** box (or `/sb craft 250`; `/sb craft max` for the cap). It reads your skill, lists the steps left (recipe, skill range, crafts), and makes a shopping list from bags and bank: parts become the materials to make them, recipes name their vendor, and what's missing is priced at your pasted AH prices. It says when to train the next rank (for Cooking: which book or quest). **Steps** and **Shopping** switch the view. Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid, on Wowhead's "Tried & Tested in Forever" routes. Parts a step makes (bolts of cloth, blasting powder, cured hides) count for later steps, and the rest are made from their materials. Recipe vendors are the ones for your faction. With more than one profession, click its name (or `/sb craft cooking`) to switch.
- **XP** (**Today** at max level): XP per hour, time to next level, kills, gold, what your loot is worth; at max level today's gold and gold per hour, loot, kills, dungeon runs, time played and your average rolls instead (`/sb today`). Also the current dungeon run with an **End run** button (or `/sb end`). A run ends by itself when you leave the area alive or leave the group outside, else 15 minutes after you step out.
- **Runs**: every dungeon run: time, kills, XP per hour, bosses (kills and wipes), loot, gold, loot value, reputation and who you ran with. Hover a run for the details. A wipe, a corpse run or waiting at the door stays the same run; another copy of the dungeon (a reset, or a new group) is a new one. At max level a kill is an enemy you see die (your target or a nameplate), since there's no XP to count. When a run ends, Snitchbot compares it with your earlier runs of that dungeon.
- **Stats**: time played per level and when you'll reach the next milestone, where this session's XP and gold came from, reputation, your Need and Greed rolls (average, highest, lowest, wins, the last five), personal bests per dungeon, who you run with most, and what each boss dropped. **Copy for snitchbot.app** puts it all on your character's page on [myself.snitchbot.app](https://myself.snitchbot.app), for you only.
- **Settings**: start the combat log in dungeons, open on entering a dungeon, tell your group, the minimap button, **Paste AH prices** (from **Copy prices for the addon** on auction.snitchbot.app) and **Probe the game**.

**Snitchbot scan**, a button above the auction house window (or `/sb scan` there), reads prices in the game: a full scan of every auction when the client allows it (once per 15 minutes), else a search of each item on your Craft and Raid lists. It keeps the lowest buyout per item; no pasting needed.

Snitchbot also warns you when your gear is low on durability as a dungeon starts.

Drag the window's bottom-right corner to make it bigger (double-click the corner for the first size); the size is kept.

Slash commands, all optional: `/sb` (open or close), `/sb craft`, `/sb craft 250`, `/sb craft cooking`, `/sb scan`, `/sb xp`, `/sb today`, `/sb runs`, `/sb stats`, `/sb check`, `/sb prices`, `/sb export`, `/sb end`, `/sb paste`, `/sb probe`.

## Development

- `Snitchbot/Code.lua`, `Tracker.lua`, `Stats.lua`: the parts with no UI (code readers, XP and run maths, bests, gold sources, buff check, the export code). `Snitchbot/Snitchbot.lua`: window, events, slash commands.
- `npm test` runs the real Lua in [fengari](https://github.com/fengari-lua/fengari) against a fake game, and checks every file parses as Lua 5.1 (WoW's version).
- Code formats shared with the website repo: the shopping code (`src/lib/shopping.ts`), the price code (`src/lib/ah/addon-prices.ts`) and the character code (`src/lib/addon-import.ts`). Change both sides together.

## Credits

- The window uses snitchbot.app's own look: charcoal, one gold accent, pill tabs and stat cards.
- [Geist](https://github.com/vercel/geist-font) font by Vercel, under the SIL Open Font License 1.1 (`Snitchbot/Media/Fonts/Geist-OFL.txt`).
