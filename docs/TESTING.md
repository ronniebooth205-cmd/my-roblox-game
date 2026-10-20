# Testing

## What has been checked without Studio

| Check | How | Result |
| --- | --- | --- |
| Syntax, unknown globals, Roblox API names | `scripts/lint.sh` (selene + luau-lsp with the Roblox type definitions) | passes; remaining luau-lsp output is strict-mode type noise (warnings, not errors) |
| Module paths / requires | luau-lsp with a Rojo sourcemap | resolves |
| Wheelie playability | `python3 tools/wheelie_sim.py` | all 4 bikes pass (see docs/PHYSICS.md) |
| Idle suspension | same simulation | settles at the designed sag with no bounce |

**Nothing has been run in Roblox Studio yet.** Everything below needs a real playtest.

## Studio checklist

Use **Test → Start** (Play), and **Test → Clients and Servers** with 2 players for multiplayer.
Look at the Output window for `[ServerMain] ... server ready` and any red errors first.

### First run
- [ ] Map builds (roads, meet, garage, town, estate, industrial, strip, countryside) with no errors.
- [ ] Player spawns on the green pad at the Volt Yard meet.
- [ ] Main menu appears with your bike on the plinth; PLAY closes it and spawns the bike.

### Bike riding
- [ ] Bike spawns in front of you, you sit on it, hands on grips and feet on pegs (R15).
- [ ] It does not sag, bounce or tip when you get on (it stays anchored until the client is ready).
- [ ] W accelerates; top speed matches the HUD (Street E-Ride ≈ 32 mph).
- [ ] S brakes; S when stopped reverses slowly; Space rear brake works.
- [ ] A/D steer; the bike leans into turns; no wobble at top speed; no flipping when turning hard.
- [ ] Wheels spin with the right speed and direction; forks and swingarm move over bumps.
- [ ] Kerbs (0.45 high) and speed bumps ride smoothly; the bike doesn't snag on part seams.
- [ ] Grass/dirt feel looser than tarmac; dust appears on dirt.

### Wheelies
- [ ] W alone doesn't wheelie; W + Left Shift lifts the front.
- [ ] Holding a wheelie with no steering keeps going straight (it used to drift off to the side);
      A/D still turn it, and it holds the new direction when you let go.
- [ ] The rear wheel stays down and the bike keeps moving while on one wheel.
- [ ] Feathering W holds the green zone on the balance meter.
- [ ] Space brings the front down; the landing is soft.
- [ ] Holding everything loops you out (crash) after roughly a second past the balance point.
- [ ] Steering works on one wheel.
- [ ] Wheelie panel shows distance/score; on landing a reward popup appears and cash/XP rise.
- [ ] Tricks (1–4) register only during wheelies and show in the trick feed.

### Camera
- [ ] Chase camera follows smoothly; C cycles Close / First person / Cinematic / Free look.
- [ ] Camera rises in wheelies so the road ahead stays visible; no clipping through walls.

### Crash and recovery
- [ ] Looping out / tipping / hitting a wall throws you off; the bike falls.
- [ ] R (or RECOVER BIKE) puts the bike upright at your last good spot and remounts you.

### Garage and shop
- [ ] G or the counter prompt opens Volt Customs; camera shows the bike on the turntable.
- [ ] Free colours apply instantly; locked colours show price/level; buying deducts cash.
- [ ] Upgrades deduct cash and change the stat bars; MAXED/level locks show correctly.
- [ ] Number plate filters bad words and shows on the bike.
- [ ] Buying a bike you can't afford, or above your level, is refused.

### Saving
- [ ] With API access on: earn cash, leave, rejoin → cash, level, bikes, paint, upgrades, settings restored.
- [ ] With API access off: a notice says progress won't save; nothing errors.
- [ ] Rejoining quickly (server hop) doesn't duplicate or lose data (session lock).

### Multiplayer (2+ players)
- [ ] Both can spawn and ride at once; each only sits on their own bike.
- [ ] You can see the other bike move smoothly, its wheels spin, steering, brake light and wheelies.
- [ ] Bikes don't collide with each other or knock people over.
- [ ] Rewards only go to the rider (try firing remotes from the command bar on a client: no cash).
- [ ] Rideout: create, invite, accept, markers over heads, meeting point marker, leave/kick.
- [ ] Leaderboard board at the meet updates after a new best wheelie.

### Platforms
- [ ] PC keyboard and mouse.
- [ ] Gamepad (Studio emulator or a real pad): triggers, sticks, B closes menus, D-pad trick selection.
- [ ] Phone landscape and portrait in the Device Emulator: touch buttons don't overlap the HUD;
      steering + throttle + wheelie work together (multi-touch).
- [ ] Tablet.
- [ ] UI scale 75% and 130% in Settings.

### Performance
- [ ] MicroProfiler / Stats: frame time with 6 riders; map part count (~6–8k parts).
- [ ] Phone emulator at Low graphics: no dust or tyre marks, stable frame rate.

### Surron-style body meshes (after importing them, see docs/BIKE_MESHES.md)
- [ ] All four bikes show the mesh frame, side covers, seat and tail, lined up with the wheels,
      forks, swingarm and head tube (check the MX Electric Pro too: it has a longer wheelbase).
- [ ] Paint changes in the garage recolour the frame, plastics, battery cover, seat and mudguard.
- [ ] Decals sit on the side covers; the ribbed seat option sits on the saddle.
- [ ] The rider sits on the seat with feet on the pegs.
- [ ] Remove one mesh from ReplicatedStorage.BikeMeshes: the bike falls back to the part-made body.

## Known gaps to check first

- Rider seat height (`RIDER_ROOT_HEIGHT_R15` in `BikeService`) is an estimate; adjust if the rider floats or sinks.
- Rider poses use joint offsets; signs of the arm/leg rotations may need flipping on some rigs.
- The challenge board text is set when the server starts and won't change at UTC midnight on a long-running server.
