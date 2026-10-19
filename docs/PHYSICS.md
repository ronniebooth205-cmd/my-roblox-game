# Bike physics

All numbers are in studs and seconds; 1 stud = 0.32 m (`GameConfig.Units`).

## Model

- **One mass.** The invisible `Chassis` part (1.6 × 2.4 × 4.2 studs) carries all of the bike's
  mass. Every visible part and the rider are massless, so the centre of mass and inertia are
  known exactly and don't change with avatars or accessories.
- **Who simulates.** A parked bike is anchored. When its owner mounts, the server unanchors it
  and gives that player network ownership; their client runs `BikeController` every
  `PreSimulation` and writes one `VectorForce` and one `Torque`. Roblox's solver integrates
  them and replicates the motion. The server re-checks anything that pays out.
- **Gravity.** Roblox gravity (196.2) makes a bike-sized pendulum fall ~2.4× faster than real
  life at this scale. An upward force at the centre of mass brings the bike down to
  `PhysicsConfig.BikeGravity` (70), which made wheelies playable.
- **Suspension.** A sphere of the wheel's radius is cast down each suspension leg. Compression
  drives a spring/damper (rate chosen so the bike sags `StaticSag` under its own weight) with a
  bump stop past `SuspensionTravel`. Spheres roll over kerbs and part seams smoothly.
- **Grip.** Drive, brakes and sideways grip act at each contact, limited by a friction circle:
  surface grip (`PhysicsConfig.Surfaces`) × tyre type (`CustomisationConfig.TyreTypes`) × bike
  grip. Forces act in the bike's centre plane so they don't fight the lean controller.
- **Motor.** Full torque at low speed, fading with `1 - (v/top)^2.2`. Regen braking off the
  throttle. Battery drains with throttle and limits power below 5%.
- **Steering.** A yaw-rate controller follows the bicycle model (`v·tan(steer)/wheelbase`),
  steering angle shrinks with speed, and a roll controller leans the bike into turns
  (`atan(v·yawRate/g)`). Steering keeps 55% authority on one wheel.

## Wheelies

Pitch is never set directly. Every frame these torques act about the centre of mass, and the
contact forces and gravity do the rest:

| Torque | Size | Notes |
| --- | --- | --- |
| Drive force | 40% of its real lever arm (`DrivePitchShare`) | The full lever arm made the nose run away in 0.25 s |
| Motor lift | `throttle × torqueCurve × WheelieLift × G0 × liftShare` | `liftShare` is 10% sitting, 100% leaning back |
| Weight shift | `lean × LeanShift × G0` | |
| Rear brake | `−RearBrakePitch × G0` | only while the front is up |
| Balance assist | `−BalanceAssist × m·g·arm × (pitch − ideal)` | within ±25° of the ideal angle only |
| Damping | `−PitchDamping × I_pivot × pitchRate` | |

`G0 = mass × BikeGravity × wheelbase/2` is gravity's torque on a flat bike about its rear axle,
so the values stay meaningful if geometry or gravity change. The natural balance point from the
geometry is ~46°; above it gravity pulls the bike over backwards, below it the nose drops.
Crashes: pitch over `FallAngle` (loop out), roll over `CrashRollAngle`, or a sudden velocity
change over `CrashImpactSpeed`.

## Tuning workflow

1. Change numbers in `PhysicsConfig.Handling` (defaults) or a bike's `Handling` in
   `BikeDefinitions`.
2. Mirror them in `tools/wheelie_sim.py` and run `python3 tools/wheelie_sim.py`. It checks that
   throttle alone doesn't wheelie, the front pops in a sensible time, a simulated player with
   0.15–0.25 s reactions can hold the wheelie, and the rear brake lands it.
3. Then playtest in Studio. The simulation is 2D and ignores roll, steering, terrain and the
   real solver, so it catches unplayable tuning but can't tell you how it *feels*.

Current results:

```
StreetERide    30° after 0.87 s, loop-out 1.37 s if held, held 6/6, lands 0.52 s after rear brake
LightBeeStyle  30° after 0.72 s, loop-out 1.10 s if held, held 6/6, lands 0.53 s
UltraEMoto     30° after 0.67 s, loop-out 1.03 s if held, held 4/6, lands 0.50 s
MXElectricPro  30° after 0.65 s, loop-out 1.00 s if held, held 4/6, lands 0.43 s
```

## Visuals vs physics

Wheel spin, suspension travel, swingarm, steering, brake light and rider poses are drawn on
every client by `BikeVisuals` and `RiderController` through `Motor6D.Transform` and joint
offsets. They never feed back into the physics.
