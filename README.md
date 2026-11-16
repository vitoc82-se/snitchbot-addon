# Snitchbot addon

The in-game half of [Snitchbot](https://forever.snitchbot.app) for WoW Forever.

- `/sb` shows your raid shopping list: what to bring, how many you have in bags and bank, what's missing.
- `/sb paste` adds a list. Copy it from **Raid list** on [auction.snitchbot.app](https://auction.snitchbot.app) with **Copy for the addon**.
- `/sb probe` makes a line to send to Snitchbot: which game functions this client has.

## Development

- `Snitchbot/Code.lua`: the parts with no UI (code reader, counts, probe). `Snitchbot/Snitchbot.lua`: window, events, slash commands.
- `npm test` runs the real Lua in [fengari](https://github.com/fengari-lua/fengari) against a fake game, and checks every file parses as Lua 5.1 (WoW's version).
- Releases: tag `vX.Y.Z` and run the [BigWigs packager](https://github.com/BigWigsMods/packager) locally (`.pkgmeta`); it uploads to CurseForge.
- The shopping code format is shared with `shoppingCode()` in the website repo (`src/lib/shopping.ts`). Change both together and bump the version in the prefix.

## Credits

- The window's look follows [Polestar](https://github.com/fitzforge/polestar)'s night style. The code is Snitchbot's own.
- [Inter](https://github.com/rsms/inter) font by The Inter Project Authors, under the SIL Open Font License 1.1 (`Snitchbot/Media/Fonts/Inter-OFL.txt`).
