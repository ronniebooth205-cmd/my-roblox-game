#!/usr/bin/env python3
"""Offline wheelie tuning check for SURRON LIFE: WHEELIE CITY.

Replays the planar (pitch) part of Controllers/BikeController.luau: sphere-cast suspension,
spring/damper loads, drive/brake at the contact (with DrivePitchShare), and the wheelie pitch
torques (lift, lean shift, rear brake, balance assist, damping). Control runs at 60 Hz and
physics at 240 Hz like Roblox. It cannot replace playtesting in Studio, but it catches tuning
that is physically unplayable (instant loop-outs, wheelies that never lift, bouncing).

Keep the numbers below in sync with PhysicsConfig.luau and BikeDefinitions.luau.

Usage:  python3 tools/wheelie_sim.py            # all bikes
        python3 tools/wheelie_sim.py MXElectricPro
"""
import math
import sys

BIKE_GRAVITY = 70.0
GEOMETRY = dict(Wheelbase=4.0, WheelRadius=1.05, MountDrop=1.3, SuspensionRest=0.9, SuspensionTravel=0.75,
                StaticSag=0.3, CastLift=0.4)
CHASSIS = (1.6, 2.4, 4.2)
DAMPING_RATIO, BUMP_STOP, STOP_SPEED = 0.55, 8, 1.2

DEFAULT = dict(TopSpeed=45, MaxAccel=28, BrakeDecel=55, FrontBrakeShare=0.65, RegenDecel=5, Grip=1.05,
               WheelieLift=1.0, PassiveLiftShare=0.1, DrivePitchShare=0.4, LeanShift=0.12, RearBrakePitch=0.9,
               IdealBalanceAngle=46, BalanceAssist=0.8, AssistWindow=25, PitchDamping=10, GroundPitchDamping=1.5,
               ThrottleResponse=0.15, FallAngle=80, WheelieThreshold=6,
               PopBoost=2.8, PopAngle=20, HighSpeedLift=0.8)

BIKES = {
    "StreetERide": dict(TopSpeed=45, MaxAccel=26, WheelieLift=1.15, BalanceAssist=0.9, PitchDamping=10,
                        ThrottleResponse=0.2, IdealBalanceAngle=44),
    "LightBeeStyle": dict(TopSpeed=66, MaxAccel=34, WheelieLift=1.3, BalanceAssist=0.9, PitchDamping=12,
                          ThrottleResponse=0.2, IdealBalanceAngle=46),
    "UltraEMoto": dict(TopSpeed=77, MaxAccel=44, WheelieLift=1.15, BalanceAssist=0.9, PitchDamping=14,
                       ThrottleResponse=0.12, RearBrakePitch=1.0, IdealBalanceAngle=48),
    "MXElectricPro": dict(TopSpeed=84, MaxAccel=50, WheelieLift=1.0, BalanceAssist=0.75, PitchDamping=12,
                          ThrottleResponse=0.12, RearBrakePitch=1.25, BrakeDecel=65, IdealBalanceAngle=50, Grip=1.12),
}


class Bike:
    def __init__(self, h, speed=0.0):
        g = GEOMETRY
        self.h, self.m = h, 1.0
        self.inertia = self.m / 12 * (CHASSIS[1] ** 2 + CHASSIS[2] ** 2)
        self.x, self.y, self.th = 0.0, g["WheelRadius"] + g["SuspensionRest"] - g["StaticSag"] + g["MountDrop"], 0.0
        self.vx, self.vy, self.w = speed, 0.0, 0.0
        self.comp = {"F": 0.0, "R": 0.0}
        self.throttle = self.lean = 0.0
        self.force, self.torque = (0.0, 0.0), 0.0
        self.pitch = 0.0
        self.front = self.rear = True

    def cast(self, lx):
        g = GEOMETRY
        f = (math.cos(self.th), math.sin(self.th))
        u = (-math.sin(self.th), math.cos(self.th))
        mx, my = self.x + lx * f[0] - g["MountDrop"] * u[0], self.y + lx * f[1] - g["MountDrop"] * u[1]
        ox, oy = mx + u[0] * g["CastLift"], my + u[1] * g["CastLift"]
        if u[1] <= 0.01:
            return None
        d = (oy - g["WheelRadius"]) / u[1]
        if d < 0 or d > g["SuspensionRest"] + g["CastLift"]:
            return None
        return d, ox - u[0] * d

    def control(self, dt, throttle, lean, rear_brake, front_brake):
        h, g, m = self.h, GEOMETRY, self.m
        self.throttle += (throttle - self.throttle) * (1 - math.exp(-dt / h["ThrottleResponse"]))
        self.lean += (lean - self.lean) * (1 - math.exp(-dt / 0.08))
        k = m * BIKE_GRAVITY / 2 / g["StaticSag"]
        c = 2 * DAMPING_RATIO * math.sqrt(k * m / 2)
        wheels = {}
        for name, lx in (("F", g["Wheelbase"] / 2), ("R", -g["Wheelbase"] / 2)):
            hit = self.cast(lx)
            prev = self.comp[name]
            if hit:
                d, px = hit
                comp = max(g["SuspensionRest"] - (d - g["CastLift"]), 0)
                speed = max(-40, min(40, (comp - prev) / dt))
                load = k * comp + c * speed
                if comp > g["SuspensionTravel"]:
                    load += k * BUMP_STOP * (comp - g["SuspensionTravel"])
                self.comp[name] = comp
                wheels[name] = (max(load, 0), px)
            else:
                self.comp[name] = 0
        total = sum(w[0] for w in wheels.values())
        fx = fy = torque = 0.0
        speed = self.vx * math.cos(self.th) + self.vy * math.sin(self.th)
        ratio = min(abs(speed) / h["TopSpeed"], 1.2)
        curve = 1 if speed < 0 else max(0.0, min(1.0, 1 - ratio ** 2.2))
        for name, (load, px) in wheels.items():
            if load <= 0:
                continue
            rx, ry = px - self.x, -self.y
            vlong = self.vx - self.w * ry
            share = load / total if total > 0 else 0.5
            max_friction = h["Grip"] * load
            lon = 0.0
            if name == "R":
                lon = m * h["MaxAccel"] * curve * self.throttle
                if self.throttle < 0.05 and abs(vlong) > 0.5:
                    lon -= math.copysign(m * h["RegenDecel"] * min(1, abs(vlong) / 3), vlong)
            brake = front_brake if name == "F" else max(rear_brake, front_brake * 0.35)
            if brake > 0:
                portion = h["FrontBrakeShare"] if name == "F" else 1 - h["FrontBrakeShare"]
                bf = m * h["BrakeDecel"] * portion * brake
                lon += -math.copysign(bf, vlong) if abs(vlong) > STOP_SPEED else max(-bf, min(bf, -vlong * m * share / dt * 0.5))
            lon = max(-max_friction, min(max_friction, lon))
            fx += lon
            fy += load
            torque += rx * load - ry * h["DrivePitchShare"] * lon
        if wheels:
            fx -= self.vx * m * 0.12
            fy -= self.vy * m * 0.12
        g0 = m * BIKE_GRAVITY * g["Wheelbase"] / 2
        arm = math.hypot(g["Wheelbase"] / 2, g["MountDrop"] + g["SuspensionRest"] - 2 * g["StaticSag"])
        self.pitch = math.degrees(self.th)
        self.rear = "R" in wheels and wheels["R"][0] > 0
        self.front = "F" in wheels and wheels["F"][0] > 0
        tp = 0.0
        if self.rear:
            lift_share = h["PassiveLiftShare"] + (1 - h["PassiveLiftShare"]) * max(self.lean, 0)
            lift_curve = max(curve, h["HighSpeedLift"])
            pop = 1 + (h["PopBoost"] - 1) * max(0.0, 1 - max(self.pitch, 0) / h["PopAngle"])
            tp += self.throttle * lift_curve * pop * h["WheelieLift"] * lift_share * g0 + self.lean * h["LeanShift"] * g0
            if not self.front and self.pitch > 0:
                tp -= rear_brake * h["RearBrakePitch"] * g0
                off = self.pitch - h["IdealBalanceAngle"]
                if self.pitch > h["WheelieThreshold"] and abs(off) < h["AssistWindow"]:
                    tp -= h["BalanceAssist"] * m * BIKE_GRAVITY * arm * math.radians(off)
                tp -= h["PitchDamping"] * (self.inertia + m * arm * arm) * self.w
            else:
                tp -= h["GroundPitchDamping"] * self.inertia * self.w
        self.force, self.torque = (fx, fy), torque + tp

    def integrate(self, dt):
        self.vx += self.force[0] / self.m * dt
        self.vy += (self.force[1] / self.m - BIKE_GRAVITY) * dt
        self.w += self.torque / self.inertia * dt
        self.x += self.vx * dt
        self.y += self.vy * dt
        self.th += self.w * dt


def simulate(h, policy, seconds, speed=0.0):
    bike, t, out, history = Bike(h, speed), 0.0, [], []
    while t < seconds:
        bike.control(1 / 60, *policy(t, history))
        for _ in range(4):
            bike.integrate(1 / 240)
        t += 1 / 60
        history.append(bike.pitch)
        out.append((t, bike.pitch, bike.front, bike.rear, bike.vx))
        if bike.pitch > h["FallAngle"] or bike.pitch < -30:
            break
    return out


def keyboard_player(target, delay, analog):
    """Pops the front, then holds lean-back and feathers throttle/rear brake with a reaction delay."""
    def policy(t, history):
        if t < 0.45:
            return 1, 1, 0, 0
        i = max(0, len(history) - 1 - int(delay * 60))
        guess = history[i] + 0.3 * (history[i] - history[max(0, i - 6)]) / 0.1
        throttle = max(0.0, min(1.0, 0.5 - (guess - target) / 15)) if analog else (1 if guess < target else 0)
        return throttle, 1, (1 if guess > target + 12 else 0), 0
    return policy


def report(name, overrides):
    h = dict(DEFAULT, **overrides)
    no_lean = max(r[1] for r in simulate(h, lambda t, hist: (1, 0, 0, 0), 5))
    pop = simulate(h, lambda t, hist: (1, 1, 0, 0), 5)
    t30 = next((r[0] for r in pop if r[1] > 30), None)
    t_loop = next((r[0] for r in pop if r[1] >= h["FallAngle"]), None)
    holds = 0
    for delay in (0.15, 0.2, 0.25):
        for analog in (False, True):
            run = simulate(h, keyboard_player(h["IdealBalanceAngle"], delay, analog), 15)
            held = [r for r in run if r[0] > 3]
            if run[-1][0] > 14.9 and held and all(not r[2] and r[3] for r in held):
                holds += 1
    fast = simulate(h, lambda t, hist: (1, 1, 0, 0), 4, speed=h["TopSpeed"] * 0.75)
    t30_fast = next((r[0] for r in fast if r[1] > 30), None)
    brake_at = (t30 or 0.6) + 0.15
    landing = simulate(h, lambda t, hist: (1, 1, 0, 0) if t < brake_at else (0, 0, 1, 0), 5)
    land = next((r[0] - brake_at for r in landing if r[0] > brake_at and r[2]), None)
    ok = no_lean < 10 and t30 is not None and t30_fast is not None and holds >= 4 and land is not None
    print(f"{'PASS' if ok else 'FAIL'} {name:14s} throttle-only max {no_lean:4.1f} deg | 30 deg after "
          f"{t30 and round(t30, 2)} s ({t30_fast and round(t30_fast, 2)} s at 75% speed), loop-out after {t_loop and round(t_loop, 2)} s if held | "
          f"held by simulated player {holds}/6 | lands {land and round(land, 2)} s after rear brake")
    return ok


if __name__ == "__main__":
    names = sys.argv[1:] or list(BIKES)
    results = [report(n, BIKES[n]) for n in names]
    sys.exit(0 if all(results) else 1)
