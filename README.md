# KGB Bots

KGB Bots is an AMX Mod X plugin for Counter-Strike 1.6 servers. It adds one or
two invisible fake clients while your configured time and player-count rules
match, then removes them when the rules no longer match.

## Features

- Creates invisible fake clients with configurable names.
- Supports one-bot and two-bot modes.
- Supports dynamic fill mode.
- Supports time windows, including overnight windows.
- Supports player-count based activation rules.
- Can wait before removing bots when rules stop matching.
- Supports servers without normal round endings.
- Creates a default config file on first load.
- Provides status and reload admin commands.
- Logs bot add/remove and config reload events.

The fake clients are hidden in-game by model/rendering state. They are not
hidden from server query metadata.

## Install

Download `kgbbots.amxx` from the latest release and copy it into:

```text
addons/amxmodx/plugins/
```

Add this line to `addons/amxmodx/configs/plugins.ini`:

```text
kgbbots.amxx
```

Start or restart the server. On first load, the plugin creates:

```text
addons/amxmodx/configs/kgbbots.cfg
```

Edit that file to change bot names, active hours, and player-count rules.

## Commands

| Command | Access | Description |
| --- | --- | --- |
| `amx_kgbbots_status` | `ADMIN_CFG` | Shows current rules, player counts, desired bots, active bots, and removal grace state. |
| `amx_kgbbots_reload` | `ADMIN_CFG` | Reloads `kgbbots.cfg` and immediately checks bot state. |

## Cvars

| Cvar | Default | Description |
| --- | --- | --- |
| `amx_botname` | `KGB Bot1` | Name for the first managed bot. |
| `amx_botname2` | `KGB Bot2` | Name for the second managed bot. Extra dynamic bots use generated names like `KGB Bot 3`. |
| `amx_minplayers` | `10` | Player-count rule. Bots are enabled when human players are less than or equal to this number. Use `0` to ignore this rule. |
| `amx_starttime` | `0` | Start hour for the time rule, using server local time, from `0` to `23`. |
| `amx_endtime` | `12` | End hour for the time rule. Same as start means all day. A range like `22` to `6` runs overnight. |
| `amx_onecon` | `0` | Rule mode. Use `0` to require both the time rule and player-count rule. Use `1` when either rule should be enough. |
| `amx_onebot` | `0` | Static bot count. Use `1` for one bot or `0` for two bots. Ignored when `amx_fillplayers` is enabled. |
| `amx_norounds` | `0` | Check mode. Use `0` for normal round-based checks. Use `1` to check every 30 seconds on servers without normal round endings. |
| `amx_maxbots` | `2` | Safety cap for managed bots, from `0` to `8`. Keep `2` for old behavior, raise it only when using dynamic fill. |
| `amx_fillplayers` | `0` | Dynamic fill target. Use `0` for static mode. Set above `0` to fill visible population up to that target, capped by `amx_maxbots`. |
| `amx_graceperiod` | `0` | Removal delay in seconds after rules stop matching. Use `0` for immediate removal or a value like `60` to avoid rapid add/remove changes. |

## Build

Docker is required for the bundled build flow.

```sh
./scripts/build.sh
```

The script downloads the pinned AMX Mod X compiler when needed, verifies it,
and writes the compiled plugin to `compiled/kgbbots.amxx`.

```sh
./scripts/check-compatibility.sh
```

Use the compatibility check to compile against AMX Mod X `1.8.2`, `1.9`, and
`1.10`.

## Release Files

- `kgbbots.amxx`
- `kgbbots.amxx.sha256`
