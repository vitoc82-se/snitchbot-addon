# Snitchbot addon

The in-game half of [Snitchbot](https://forever.snitchbot.app) for WoW Forever.

One window with four tabs. Open it with the minimap button (or `/sb`); it stays open over reloads until you close it.

- **Raid list**: what to bring for raid night, how many you have in bags and bank, what's missing. **New list** pastes the code from **Raid list** on [auction.snitchbot.app](https://auction.snitchbot.app) (**Copy for the addon**).
- **XP**: XP per hour, time to next level, kills, and the current dungeon run.
- **Runs**: every dungeon run: time, kills, XP per hour, bosses (kills and wipes), loot, gold and who you ran with. Hover a run for the details. Runs start and end by themselves, and Snitchbot says in group chat that it's tracking the run (Settings → Tell my group).
- **Settings**: start the combat log in dungeons, open on entering a dungeon, the minimap button, and **Probe the game**.

## Development

- `Snitchbot/Code.lua`: the parts with no UI (code reader, counts, probe). `Snitchbot/Snitchbot.lua`: window, events, slash commands.
- `npm test` runs the real Lua in [fengari](https://github.com/fengari-lua/fengari) against a fake game, and checks every file parses as Lua 5.1 (WoW's version).
- Releases: tag `vX.Y.Z` and run the [BigWigs packager](https://github.com/BigWigsMods/packager) locally (`.pkgmeta`); it uploads to CurseForge.
- The shopping code format is shared with `shoppingCode()` in the website repo (`src/lib/shopping.ts`). Change both together and bump the version in the prefix.

## Credits

- The window's look follows [Polestar](https://github.com/fitzforge/polestar)'s night style. The code is Snitchbot's own.
- [Inter](https://github.com/rsms/inter) font by The Inter Project Authors, under the SIL Open Font License 1.1 (`Snitchbot/Media/Fonts/Inter-OFL.txt`).
