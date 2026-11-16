# Snitchbot addon

The in-game half of [Snitchbot](https://forever.snitchbot.app) for WoW Forever.

One window with five tabs. Open it with the minimap button (or `/sb`); it stays open over reloads until you close it, and remembers where you put it.

- **Raid list**: what to bring for raid night, how many you have in bags and bank, what's missing. **New list** pastes the code from **Raid list** on [auction.snitchbot.app](https://auction.snitchbot.app) (**Copy for the addon**). **Check buffs** lists who in your group has no flask, no elixir or no food, and how many have world buffs.
- **XP**: XP per hour, time to next level, kills, gold, what your loot is worth, and the current dungeon run with an **End run** button.
- **Runs**: every dungeon run: time, kills, XP per hour, bosses (kills and wipes), loot, gold, loot value, reputation and who you ran with. Hover a run for the details. A wipe, a corpse run or waiting at the door stays the same run. When a run ends, Snitchbot compares it with your earlier runs of that dungeon.
- **Stats**: time played per level and when you'll reach the next milestone, where this session's XP and gold came from, reputation, personal bests per dungeon, who you run with most, and what each boss dropped. **Copy for snitchbot.app** puts it all on your character's page on [myself.snitchbot.app](https://myself.snitchbot.app), for you only.
- **Settings**: start the combat log in dungeons, open on entering a dungeon, tell your group, the minimap button, **Paste AH prices** (from **Copy prices for the addon** on auction.snitchbot.app) and **Probe the game**.

Snitchbot also warns you when your gear is low on durability as a dungeon starts.

Slash commands, all optional: `/sb` (open or close), `/sb xp`, `/sb runs`, `/sb stats`, `/sb check`, `/sb prices`, `/sb export`, `/sb paste`, `/sb probe`.

## Development

- `Snitchbot/Code.lua`, `Tracker.lua`, `Stats.lua`: the parts with no UI (code readers, XP and run maths, bests, gold sources, buff check, the export code). `Snitchbot/Snitchbot.lua`: window, events, slash commands.
- `npm test` runs the real Lua in [fengari](https://github.com/fengari-lua/fengari) against a fake game, and checks every file parses as Lua 5.1 (WoW's version).
- Code formats shared with the website repo: the shopping code (`src/lib/shopping.ts`), the price code (`src/lib/ah/addon-prices.ts`) and the character code (`src/lib/addon-import.ts`). Change both sides together.

## Credits

- The window uses snitchbot.app's own look: charcoal, one gold accent, pill tabs and stat cards.
- [Geist](https://github.com/vercel/geist-font) font by Vercel, under the SIL Open Font License 1.1 (`Snitchbot/Media/Fonts/Geist-OFL.txt`).
