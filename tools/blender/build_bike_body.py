"""Builds the Surron-style bike body in Blender and exports it for Roblox.

Makes one mesh per paint slot (Frame, BatteryCover, Plastics, Seat, Mudguards) in the same
space as BikeBuilder.luau (studs, chassis centre at the origin, forward is -Z, ground at
y = -2.95 for the standard geometry). Wheels, forks, bars, swingarm, motor and shock stay as
Roblox parts because they move and are customised separately.

Outputs (next to this script, in out/):
  bike_body.blend          the editable Blender file (preview stand-ins are in the "Preview" collection)
  <Slot>.obj               one mesh per slot, Y-up stud coordinates, ready for Studio's 3D Importer
  BikeMeshLayout.luau      each mesh's centre and size; copy to src/ReplicatedStorage/Shared/
  preview.png, preview_side.png   renders with stand-in wheels and forks (with --render)

Run with Blender:   blender --background --python tools/blender/build_bike_body.py -- --render
or the bpy module:  python3 tools/blender/build_bike_body.py --render

Then follow docs/BIKE_MESHES.md to import the meshes into Studio.
"""
import math
import os
import sys

import bpy  # first: the bpy module makes bmesh and mathutils importable
import bmesh  # noqa: E402
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

# Must match PhysicsConfig.Geometry and the Standard style in BikeBuilder.luau.
WHEELBASE, WHEEL_R = 4.0, 1.05
AXLE_Y = -(1.3 + 0.9 - 0.3)
GROUND_Y = AXLE_Y - WHEEL_R
RAKE = math.radians(18.5)
HEAD_TOP_H = 3.0
AXIS_UP = (0.0, math.cos(RAKE), math.sin(RAKE))
FORK_LEN = (HEAD_TOP_H - WHEEL_R) / math.cos(RAKE)
FRONT_AXLE = (0.0, AXLE_Y, -WHEELBASE / 2)
REAR_AXLE = (0.0, AXLE_Y, WHEELBASE / 2)
HEAD_TOP = tuple(FRONT_AXLE[i] + AXIS_UP[i] * FORK_LEN for i in range(3))
HEAD_BOTTOM = tuple(HEAD_TOP[i] - AXIS_UP[i] * 0.6 for i in range(3))
PIVOT = (0.0, GROUND_Y + 1.3, 0.6)

# Side panels: outer face of the plastics, where BikeBuilder puts the decals.
PANEL_X, PANEL_T = 0.385, 0.05

SLOT_COLOURS = {  # default paint, for the preview only
    "Frame": (58, 60, 64),
    "BatteryCover": (22, 22, 24),
    "Plastics": (57, 255, 136),
    "Seat": (22, 22, 24),
    "Mudguards": (22, 22, 24),
}


def rb(x, y, z):
    """Roblox (x right, y up, z back) to Blender (x right, y forward, z up)."""
    return Vector((x, -z, y))


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def catmull(points, steps):
    """Smooth a polyline through its points (Catmull-Rom)."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (Vector(p) for p in pts[i - 1:i + 3])
        for s in range(steps):
            t = s / steps
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    out.append(Vector(points[-1]))
    return out


def rounded_rect(w, h, r, seg=3):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180),
                       (w / 2 - r, -h / 2 + r, 270)):
        for s in range(seg + 1):
            a = math.radians(a0 + 90 * s / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def sweep(bm, path_rb, width, height, radius=0.04, steps=6):
    """Box-section tube along a smoothed path (Roblox coords), profile kept upright to the side."""
    path = catmull([rb(*p) for p in path_rb], steps)
    profile = rounded_rect(width, height, min(radius, width / 2 - 1e-3, height / 2 - 1e-3))
    rings = []
    for i, p in enumerate(path):
        tangent = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = Vector((1, 0, 0))
        up = tangent.cross(side).normalized()
        if up.z < 0:
            up = -up
        side = up.cross(tangent).normalized()
        rings.append([bm.verts.new(p + side * px + up * py) for px, py in profile])
    n = len(profile)
    for a, b in zip(rings, rings[1:]):
        for j in range(n):
            bm.faces.new((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def cylinder(bm, a_rb, b_rb, radius, seg=16):
    a, b = rb(*a_rb), rb(*b_rb)
    axis = (b - a).normalized()
    side = axis.orthogonal().normalized()
    up = axis.cross(side)
    ring_a, ring_b = [], []
    for s in range(seg):
        ang = 2 * math.pi * s / seg
        off = (side * math.cos(ang) + up * math.sin(ang)) * radius
        ring_a.append(bm.verts.new(a + off))
        ring_b.append(bm.verts.new(b + off))
    for j in range(seg):
        bm.faces.new((ring_a[j], ring_b[j], ring_b[(j + 1) % seg], ring_a[(j + 1) % seg]))
    bm.faces.new(ring_a)
    bm.faces.new(list(reversed(ring_b)))


def side_slab(bm, profile_zy, x0, x1):
    """Extrude a side-view outline (Roblox z, y pairs, any winding) between x0 and x1."""
    left = [bm.verts.new(rb(x0, y, z)) for z, y in profile_zy]
    right = [bm.verts.new(rb(x1, y, z)) for z, y in profile_zy]
    n = len(profile_zy)
    for j in range(n):
        bm.faces.new((left[j], left[(j + 1) % n], right[(j + 1) % n], right[j]))
    bm.faces.new(left)
    bm.faces.new(list(reversed(right)))


def top_slab(bm, outline_xz, y_of_z, thickness):
    """Extrude a top-view outline (Roblox x, z pairs) downwards from a surface whose height
    follows the z position (for the sloping tail)."""
    top = [bm.verts.new(rb(x, y_of_z(z), z)) for x, z in outline_xz]
    bottom = [bm.verts.new(rb(x, y_of_z(z) - thickness, z)) for x, z in outline_xz]
    n = len(outline_xz)
    for j in range(n):
        bm.faces.new((top[j], bottom[j], bottom[(j + 1) % n], top[(j + 1) % n]))
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))


def make_object(name, build, bevel=0.0, bevel_segments=2, collection=None, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    (collection or bpy.context.scene.collection).objects.link(obj)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = bevel_segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
    if smooth:
        # Smooth shading with sharp edges kept above 40 degrees.
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
        obj.select_set(False)
    return obj


# ------------------------------------------------------------------ the body, one function per slot

def build_frame(bm):
    for s in (-1, 1):
        # Main spar: from the head tube, back over the battery, then down to the swingarm pivot.
        sweep(bm, [
            (s * 0.2, HEAD_TOP[1] - 0.22, HEAD_TOP[2] - 0.05),
            (s * 0.31, -0.32, -1.0),
            (s * 0.34, -0.42, -0.2),
            (s * 0.35, -0.62, 0.32),
            (s * 0.37, -1.05, 0.52),
            (s * 0.38, PIVOT[1] + 0.05, PIVOT[2]),
        ], 0.13, 0.34, steps=8)
        # Lower cradle: head tube down under the battery to the motor mount.
        sweep(bm, [
            (s * 0.1, HEAD_BOTTOM[1] - 0.05, HEAD_BOTTOM[2] + 0.02),
            (s * 0.27, -1.15, -1.32),
            (s * 0.31, -1.5, -1.05),
            (s * 0.33, -1.62, -0.4),
            (s * 0.37, -1.72, 0.25),
            (s * 0.38, PIVOT[1] - 0.05, PIVOT[2]),
        ], 0.11, 0.2, steps=8)
        # Subframe under the seat and its stay from the pivot.
        sweep(bm, [(s * 0.3, -0.52, 0.2), (s * 0.27, -0.36, 1.1), (s * 0.21, -0.25, 2.2)], 0.08, 0.13, steps=6)
        sweep(bm, [(s * 0.36, -1.25, 0.58), (s * 0.3, -0.8, 1.0), (s * 0.25, -0.4, 1.6)], 0.07, 0.1, steps=6)
        # Pivot plate.
        side_slab(bm, [(0.3, -1.25), (0.85, -1.4), (0.85, -1.9), (0.35, -1.95)], s * 0.35, s * 0.43)
    cylinder(bm, tuple(HEAD_BOTTOM[i] - AXIS_UP[i] * 0.1 for i in range(3)),
             tuple(HEAD_TOP[i] + AXIS_UP[i] * 0.05 for i in range(3)), 0.17, seg=20)
    # Cross braces holding the two sides together.
    cylinder(bm, (-0.36, -0.66, 0.3), (0.36, -0.66, 0.3), 0.07)
    cylinder(bm, (-0.36, PIVOT[1], PIVOT[2]), (0.36, PIVOT[1], PIVOT[2]), 0.08)
    cylinder(bm, (-0.22, -0.28, 2.1), (0.22, -0.28, 2.1), 0.05)


def build_battery(bm):
    # Sits between the frame rails; the bottom matches the procedural skid plate.
    side_slab(bm, [(-1.25, -0.32), (0.08, -0.38), (0.08, -1.35), (-0.95, -1.35), (-1.28, -0.95)], -0.3, 0.3)


def build_plastics(bm):
    # The big side covers over the battery (where the decals go).
    cover = [(-1.36, -0.1), (0.36, -0.13), (0.3, -0.62), (-0.32, -1.3), (-0.98, -1.3), (-1.36, -0.66)]
    for s in (-1, 1):
        side_slab(bm, cover, s * (PANEL_X - PANEL_T), s * PANEL_X)
        # Rear side panels under the seat, sweeping up to the tail.
        side_slab(bm, [(0.3, -0.1), (1.6, -0.06), (2.62, -0.14), (2.5, -0.3), (0.62, -0.72), (0.3, -0.62)],
                  s * 0.2, s * 0.27)
    # Top cover between the head tube and the seat (the "tank").
    side_slab(bm, [(-1.36, -0.12), (-1.12, 0.02), (-0.7, 0.05), (-0.62, -0.1), (-0.66, -0.36), (-1.36, -0.34)],
              -0.33, 0.33)


def build_seat(bm):
    # Long flat saddle; its top sits where the rider's Seat part is.
    side_slab(bm, [(-0.78, -0.04), (-0.58, 0.07), (1.3, 0.09), (1.6, 0.05), (1.62, -0.1), (0.2, -0.16), (-0.78, -0.16)],
              -0.25, 0.25)


def build_mudguard(bm):
    # Pointed rear fender that ends just above the tail light.
    outline = [(-0.2, 1.2), (-0.19, 2.45), (-0.08, 2.86), (0.08, 2.86), (0.19, 2.45), (0.2, 1.2)]
    top_slab(bm, outline, lambda z: -0.1 - 0.07 * (z - 1.2), 0.05)


SLOTS = [
    ("Frame", build_frame, 0.0),
    ("BatteryCover", build_battery, 0.06),
    ("Plastics", build_plastics, 0.02),
    ("Seat", build_seat, 0.07),
    ("Mudguards", build_mudguard, 0.015),
]


# ------------------------------------------------------------------ preview stand-ins (not exported)

def build_preview_parts(collection):
    def wheel(bm, centre, radius, width):
        cylinder(bm, (-width, centre[1], centre[2]), (width, centre[1], centre[2]), radius, seg=40)

    make_object("PreviewWheels", lambda bm: (wheel(bm, FRONT_AXLE, WHEEL_R, 0.21), wheel(bm, REAR_AXLE, WHEEL_R, 0.21)),
                0.08, 3, collection)
    make_object("PreviewRims", lambda bm: (wheel(bm, FRONT_AXLE, WHEEL_R * 0.74, 0.23), wheel(bm, REAR_AXLE, WHEEL_R * 0.74, 0.23)),
                0.0, 2, collection)

    def forks(bm):
        for s in (-1, 1):
            bottom = (s * 0.38, FRONT_AXLE[1], FRONT_AXLE[2])
            cylinder(bm, bottom, tuple(HEAD_TOP[i] + (s * 0.38 if i == 0 else 0) for i in range(3)), 0.12)
        top = HEAD_TOP
        bar = (0, top[1] + 0.66, top[2] + 0.22)
        cylinder(bm, top, bar, 0.12)
        cylinder(bm, (-1.22, bar[1], bar[2]), (1.22, bar[1], bar[2]), 0.065)
        # Number board with the round light.
        mid = tuple(HEAD_TOP[i] - AXIS_UP[i] * 0.35 for i in range(3))
        side_slab(bm, [(mid[2] - 0.34, mid[1] + 0.45), (mid[2] - 0.42, mid[1] - 0.5), (mid[2] - 0.3, mid[1] - 0.5),
                       (mid[2] - 0.24, mid[1] + 0.45)], -0.47, 0.47)

    make_object("PreviewForks", forks, 0.02, 2, collection)

    def swingarm(bm):
        for s in (-1, 1):
            sweep(bm, [(s * 0.37, PIVOT[1], PIVOT[2]), (s * 0.37, REAR_AXLE[1], REAR_AXLE[2])], 0.12, 0.3)
        cylinder(bm, (-0.3, PIVOT[1] + 0.05, 0.05), (0.3, PIVOT[1] + 0.05, 0.05), 0.38)  # motor
        cylinder(bm, (0, -0.5, 0.15), (0, -1.2, 0.75), 0.15)  # shock

    make_object("PreviewSwingarm", swingarm, 0.02, 2, collection)


def material(name, rgb, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*(c / 255 for c in rgb), 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


# ------------------------------------------------------------------ export

def export_obj(obj, path):
    """Write the evaluated mesh as a triangulated OBJ in Roblox coordinates (Y up, studs)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = obj.evaluated_get(depsgraph).to_mesh()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.normal_update()
    to_rb = lambda v: (v.x, v.z, -v.y)  # noqa: E731
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    lines = [f"# {obj.name} - Bubble bike body, Roblox studs, Y up\n", f"o {obj.name}\n"]
    for v in bm.verts:
        p = to_rb(v.co)
        for i in range(3):
            lo[i], hi[i] = min(lo[i], p[i]), max(hi[i], p[i])
        lines.append("v %.5f %.5f %.5f\n" % p)
    normals = []
    faces = []
    for f in bm.faces:
        idx = []
        for loop in f.loops:
            n = loop.vert.normal if f.smooth else f.normal
            normals.append("vn %.4f %.4f %.4f\n" % to_rb(n))
            idx.append(f"{loop.vert.index + 1}//{len(normals)}")
        faces.append("f " + " ".join(idx) + "\n")
    lines += normals + faces
    with open(path, "w") as fh:
        fh.writelines(lines)
    tris = len(bm.faces)
    bm.free()
    obj.evaluated_get(depsgraph).to_mesh_clear()
    centre = tuple((lo[i] + hi[i]) / 2 for i in range(3))
    size = tuple(hi[i] - lo[i] for i in range(3))
    return centre, size, tris


def write_layout(entries, path):
    lines = [
        "--!strict\n",
        "-- ReplicatedStorage > Shared > BikeMeshLayout (ModuleScript)\n",
        "-- Generated by tools/blender/build_bike_body.py - don't edit by hand, re-run the script.\n",
        "-- Where each imported body mesh goes on the bike (centre and size of its bounding box in the\n",
        "-- bike's own space, studs, forward is -Z). Studio's importer centres each mesh on its bounding\n",
        "-- box, so BikeBuilder places it at Centre and sets Size, whatever scale it was imported at.\n",
        "\n",
        "return {\n",
        f"\tPanelOuterX = {PANEL_X}, -- outer face of the side covers, where decals sit\n",
        "\tMeshes = {\n",
    ]
    for name, (centre, size, tris) in entries.items():
        c = ", ".join("%.4f" % v for v in centre)
        s = ", ".join("%.4f" % v for v in size)
        lines.append(f"\t\t{name} = {{ Centre = Vector3.new({c}), Size = Vector3.new({s}) }}, -- {tris} triangles\n")
    lines += ["\t},\n", "}\n"]
    with open(path, "w") as fh:
        fh.writelines(lines)


def render(path):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.device = "CPU"
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.82, 0.86, 0.9, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scene.world = world
    ground = bpy.data.meshes.new("Ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=20)
    bm.to_mesh(ground)
    bm.free()
    g = bpy.data.objects.new("Ground", ground)
    g.location = (0, 0, GROUND_Y)
    g.data.materials.append(material("GroundMat", (90, 92, 96), roughness=0.9))
    scene.collection.objects.link(g)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-40))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 40
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, -1.3))
    for suffix, location in (("", (7.5, 4.2, 0.6)), ("_side", (10.5, 0.0, -1.0))):
        cam.location = Vector(location)
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = path.replace(".png", suffix + ".png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = bpy.data.collections.new("Body")
    bpy.context.scene.collection.children.link(body)
    preview = bpy.data.collections.new("Preview")
    bpy.context.scene.collection.children.link(preview)

    entries = {}
    for name, build, bevel in SLOTS:
        obj = make_object(name, build, bevel, 2, body)
        metallic = 0.6 if name == "Frame" else 0.0
        obj.data.materials.append(material(name + "Mat", SLOT_COLOURS[name], metallic, 0.35 if metallic else 0.55))
        entries[name] = export_obj(obj, os.path.join(OUT, name + ".obj"))
        print(f"{name}: {entries[name][2]} triangles")
    write_layout(entries, os.path.join(OUT, "BikeMeshLayout.luau"))

    build_preview_parts(preview)
    dark = material("PreviewDark", (28, 28, 30), 0.2, 0.6)
    metal = material("PreviewMetal", (150, 154, 160), 0.8, 0.3)
    for obj in preview.objects:
        obj.data.materials.append(metal if obj.name == "PreviewRims" else dark)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "bike_body.blend"))
    if "--render" in argv:
        render(os.path.join(OUT, "preview.png"))


main()
