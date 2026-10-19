# Setup

## One-time (Windows)

1. Install **Git** (https://git-scm.com/download/win) and **Rojo**
   (https://github.com/rojo-rbx/rojo/releases, put `rojo.exe` somewhere on your PATH).
2. `rojo plugin install` to add the Rojo plugin to Studio.
3. `git clone https://github.com/ronniebooth205-cmd/my-roblox-game.git`

## Every session

```
cd C:\Users\Jamie\my-roblox-game
git pull
rojo serve
```

In Studio: **Plugins → Rojo → Connect**. Rojo syncs `ReplicatedStorage`, `ServerScriptService`
and `StarterPlayer > StarterPlayerScripts`. Anything else you built by hand in Studio is left
alone (`$ignoreUnknownInstances`).

## Studio settings to turn on

- **Game Settings → Security → Enable Studio Access to API Services**: needed for saving.
  Without it the game still runs; every player gets a temporary profile and a notice saying
  progress won't save.
- **Game Settings → Security → Allow HTTP Requests** is *not* needed.
- **Workspace.StreamingEnabled**: recommended **on** for the published game (the map is built
  in zones and the client waits for bikes to stream in). Test with it on and off.
- Avatar type: R15 is recommended (hands and feet attach to the bars and pegs with IK). R6
  works but keeps the default sitting pose.

## Things the game changes at runtime

- Builds `Workspace.Map` (city) and `Workspace.Bikes` when the server starts. Edits you make to
  `Workspace.Map` in Studio are replaced every run; change `MapLayout`/`MapGenerator` instead.
- Hides a part called `Baseplate` for the session (it would z-fight with the city ground).
  Turn this off with `HIDE_DEFAULT_BASEPLATE` in `Services/MapService.luau`.
- Sets lighting (time of day, atmosphere, colour grading) in `MapService`.
- Registers collision groups `Bikes`, `Riders`, `Characters`, `BikeRay`.

## Adding sounds

`src/ReplicatedStorage/Shared/AudioConfig.luau` lists every sound slot. Paste
`rbxassetid://` IDs for licensed sounds you own or that are free to use; empty slots are
skipped.

## Publishing checklist

- Turn on API access (above) and test a save/rejoin.
- Set the server size in **Game Settings → Places** (the game has no hard player cap of its own).
- Check the codes in `EconomyConfig.Codes` before announcing them.
