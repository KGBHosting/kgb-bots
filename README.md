# KGB Bots

KGB Bots is an AMX Mod X plugin for Counter-Strike 1.6 servers. It adds one or
two invisible fake clients while your configured time and player-count rules
match, then removes them when the rules no longer match.

## Features

- Creates invisible fake clients with configurable names.
- Supports one-bot and two-bot modes.
- Supports time windows, including overnight windows.
- Supports player-count based activation rules.
- Supports servers without normal round endings.
- Creates a default config file on first load.

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

## Cvars

| Cvar | Default | Description |
| --- | --- | --- |
| `amx_botname` | `KGB Bot1` | First bot name. |
| `amx_botname2` | `KGB Bot2` | Second bot name. |
| `amx_minplayers` | `10` | Enable bots when human players are less than or equal to this value. Use `0` to ignore player count. |
| `amx_starttime` | `0` | Start hour, `0`-`23`. |
| `amx_endtime` | `12` | End hour, `0`-`23`. Same as start means all day. |
| `amx_onecon` | `0` | Use `1` when either the time rule or player-count rule is enough. Use `0` to require both. |
| `amx_onebot` | `0` | Use `1` to manage only one bot. |
| `amx_norounds` | `0` | Use `1` to check rules every 30 seconds instead of relying on round events. |

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
