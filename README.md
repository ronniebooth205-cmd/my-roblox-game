# SURRON LIFE: WHEELIE CITY

An original Roblox electric dirt bike game: ride a physically simulated e-bike around a
UK-inspired city, pull long skill-based wheelies, land tricks, earn cash and XP, and customise
your bike with friends. All code, bike models and the map are generated from the Luau in this
repo; every name and brand in the game is fictional.

> **Status:** the whole first version is implemented, and the wheelie physics was tuned against
> an offline simulation (`tools/wheelie_sim.py`). **None of it has been playtested in Roblox
> Studio yet.** Expect tuning and layout fixes after the first real session; see
> [docs/TESTING.md](docs/TESTING.md).

## Quick start (Windows)

```
cd C:\Users\Jamie\my-roblox-game
git pull
rojo serve
```

In Studio: open your place, **Plugins → Rojo → Connect**, then press **Play**. The server builds
the map at startup, so the first few seconds of a test show an empty sky. Full details in
[docs/SETUP.md](docs/SETUP.md).

## What's in the game

| Area | What it does |
| --- | --- |
| Bikes | 4 bikes (Street E-Ride 60V, Light Bee Style 72V, Ultra E-Moto 80V, MX Electric Pro), each built from ~80 parts: frame, battery, motor, swingarm, shock, chain, forks, bars, grips, levers, spoked wheels, discs, lights, plate |
| Physics | Sphere-cast suspension, friction-circle grip by surface and tyre, electric torque curve, front/rear brakes, lean-steering, real pitch dynamics for wheelies with a configurable balance assist |
| Tricks | One-hander, no-hander, standing, seat tap, leg out, slow balance, sky high, combo |
| World | Generated city: bike meet + garage, high street, petrol station, supermarket, town square, estate (terraces, semis, lock-ups, park), industrial estate with a practice yard, Victoria Park, a 700 m wheelie strip with distance markers, countryside with hills, stream, bridge, dirt track and fields |
| Progress | Cash, XP, levels, unlocks, milestones, 3 daily challenges, codes, exploration rewards, leaderboards |
| Garage | Paint 15 parts in 17 colours, bars/tyres/wheels/discs/seat/decals/reflective trim, 6 performance upgrades, controller tuning, number plate (filtered) |
| Multiplayer | Up to the server's player limit, rideout groups with invites, markers and meeting points, replicated steering/lean/brake light/pose |
| UI | Dark theme with electric-green accent: HUD, speedometer, wheelie/balance panel, main menu, garage, shop, settings with key rebinding, progress, map, rideouts, touch controls |

## Layout

```
default.project.json          Rojo project
src/ReplicatedStorage/Shared  Config and shared logic (both sides)
  GameConfig                  units, spawning, data store, camera, settings schema
  PhysicsConfig               bike physics constants and default tuning
  BikeDefinitions             the four bikes
  BikeStats                   final stats from bike + upgrades + tuning
  BikeBuilder                 builds the bike model from parts
  CustomisationConfig         paint, parts, upgrades, tuning ranges
  TrickDefinitions            tricks and their rules
  EconomyConfig               scoring, rewards, levels, challenges, codes
  MapLayout                   roads, zones, key places
  AudioConfig                 sound IDs (empty until you add licensed sounds)
  Remotes, Utilities
src/ServerScriptService
  ServerMain                  starts services in order
  Services/                   PlayerData, Economy, Map, Bike, Trick, Challenge, Garage, Multiplayer
  Map/                        MapGenerator + MapBuilders
src/StarterPlayer/StarterPlayerScripts
  ClientMain                  riding lifecycle and wiring
  Controllers/                Input, Bike (physics), Wheelie, Trick, Camera, BikeVisuals, Rider, Audio, ClientState
  UI/                         Theme, Components, HUD, MobileControls, MainMenu, Garage, Shop, Settings, Progress, Map, Rideout, UIController
tools/wheelie_sim.py          offline wheelie tuning check
tools/blender/                Blender script for the Surron-style body meshes (see docs/BIKE_MESHES.md)
docs/                         SETUP, CONTROLS, PHYSICS, TESTING, UI, BIKE_MESHES
```

## Rules of the codebase

- The server decides everything that matters: cash, XP, purchases, ownership, rewards, saves.
  The client only predicts (e.g. the wheelie score on the HUD).
- Every tunable lives in a config module, not in the code that uses it.
- Run `scripts/lint.sh` after changes and `python3 tools/wheelie_sim.py` after touching
  wheelie or bike numbers.
