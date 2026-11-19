class_name Rig
extends Node3D
## Chunky low-poly body (about 2.5 heads tall) built from boxes. Origin at the feet,
## facing +X. The same part table drives the ragdoll, so corpses match the living body.
## A Body node under the rig carries squash-and-stretch and lean.

## name: [size, rest centre, mass, palette slot]
const PARTS := {
	"torso":   [Vector3(0.42, 0.40, 0.50), Vector3(0, 0.52, 0), 12.0, "shirt"],
	"head":    [Vector3(0.46, 0.44, 0.44), Vector3(0, 0.95, 0), 5.0, "skin"],
	"thigh_f": [Vector3(0.17, 0.17, 0.17), Vector3(0, 0.235, 0.13), 2.5, "pants"],
	"thigh_b": [Vector3(0.17, 0.17, 0.17), Vector3(0, 0.235, -0.13), 2.5, "pants"],
	"shin_f":  [Vector3(0.18, 0.16, 0.18), Vector3(0, 0.08, 0.13), 2.0, "boots"],
	"shin_b":  [Vector3(0.18, 0.16, 0.18), Vector3(0, 0.08, -0.13), 2.0, "boots"],
	"arm_f":   [Vector3(0.13, 0.32, 0.13), Vector3(0, 0.52, 0.32), 1.5, "sleeve"],
	"arm_b":   [Vector3(0.13, 0.32, 0.13), Vector3(0, 0.52, -0.32), 1.5, "sleeve"],
}

## [parent, child, pivot, lower deg, upper deg] (positive = rotating toward facing)
const JOINTS := [
	["torso", "head", Vector3(0, 0.73, 0), -30.0, 30.0],
	["torso", "thigh_f", Vector3(0, 0.32, 0.13), -40.0, 110.0],
	["torso", "thigh_b", Vector3(0, 0.32, -0.13), -40.0, 110.0],
	["thigh_f", "shin_f", Vector3(0, 0.155, 0.13), -130.0, 0.0],
	["thigh_b", "shin_b", Vector3(0, 0.155, -0.13), -130.0, 0.0],
	["torso", "arm_f", Vector3(0, 0.68, 0.32), -170.0, 170.0],
	["torso", "arm_b", Vector3(0, 0.68, -0.32), -170.0, 170.0],
]

const PLAYER_PALETTE := {
	"shirt": Color(0.12, 0.42, 0.95), "skin": Color(0.96, 0.74, 0.58),
	"pants": Color(0.14, 0.14, 0.22), "boots": Color(0.95, 0.95, 0.98),
	"sleeve": Color(0.12, 0.42, 0.95), "accent": Color(1.0, 0.45, 0.1),
	"eyes": Color(0.08, 0.06, 0.1),
}
const ENEMY_PALETTE := {
	"shirt": Color(0.78, 0.18, 0.16), "skin": Color(0.86, 0.66, 0.52),
	"pants": Color(0.32, 0.3, 0.3), "boots": Color(0.12, 0.1, 0.1),
	"sleeve": Color(0.78, 0.18, 0.16), "accent": Color(0.15, 0.12, 0.12),
	"eyes": Color(0.95, 0.9, 0.2),
}

const YAW := 0.45  # turn toward the camera so the box people read as bodies
const CHEST := 0.6

var palette: Dictionary = ENEMY_PALETTE
var body: Node3D
var pivots := {}
var neck: Node3D
var hip_f: Node3D
var hip_b: Node3D
var knee_f: Node3D
var knee_b: Node3D
var shoulder_f: Node3D
var shoulder_b: Node3D
var facing := 0.0

var squash := 1.0       # 1 = rest, <1 squashed, >1 stretched
var _squash_vel := 0.0
var lean := 0.0         # radians, positive = leaning forward
var _phase := 0.0


static func part_mesh(part: String, pal: Dictionary) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = PARTS[part][0]
	b.material = Game.mat(pal[PARTS[part][3]])
	m.mesh = b
	return m


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	pivots["torso"] = body
	var pivot_at := {"torso": Vector3.ZERO}
	var torso := part_mesh("torso", palette)
	torso.position = PARTS["torso"][1]
	body.add_child(torso)
	for j in JOINTS:
		var p := Node3D.new()
		p.position = j[2] - pivot_at[j[0]]
		pivots[j[0]].add_child(p)
		pivots[j[1]] = p
		pivot_at[j[1]] = j[2]
		var m := part_mesh(j[1], palette)
		m.position = PARTS[j[1]][1] - j[2]
		p.add_child(m)
	neck = pivots["head"]
	hip_f = pivots["thigh_f"]
	hip_b = pivots["thigh_b"]
	knee_f = pivots["shin_f"]
	knee_b = pivots["shin_b"]
	shoulder_f = pivots["arm_f"]
	shoulder_b = pivots["arm_b"]

	_box(body, Vector3(0.44, 0.07, 0.52), Vector3(0, 0.36, 0), palette["accent"])        # belt
	_box(neck, Vector3(0.48, 0.08, 0.46), Vector3(0, 0.36, 0), palette["accent"])        # headband
	_box(neck, Vector3(0.03, 0.1, 0.07), Vector3(0.235, 0.24, 0.1), palette["eyes"])     # eyes
	_box(neck, Vector3(0.03, 0.1, 0.07), Vector3(0.235, 0.24, -0.1), palette["eyes"])


func _box(parent: Node3D, size: Vector3, at: Vector3, c: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = Game.mat(c)
	m.mesh = b
	m.position = at
	parent.add_child(m)


func face(f: float) -> void:
	if f == facing:
		return
	facing = f
	scale.x = f
	rotation.y = -YAW * f
	reset_physics_interpolation()


## Kick the squash spring: negative squashes (landing), positive stretches (launch).
func punch(amount: float) -> void:
	_squash_vel += amount


func update_body(dt: float) -> void:
	_squash_vel += (180.0 * (1.0 - squash) - 14.0 * _squash_vel) * dt
	squash = clampf(squash + _squash_vel * dt, 0.55, 1.5)
	var side := 1.0 / sqrt(squash)
	body.scale = Vector3(side, squash, side)
	body.rotation.z = -lean


## Legs: run cycle on the ground, tuck in the air.
func animate_legs(speed: float, on_floor: bool, dt: float) -> void:
	var w := 1.0 - exp(-18.0 * dt)
	var hf := 0.0
	var hb := 0.0
	var kf := -0.05
	var kb := -0.05
	if on_floor and speed > 0.3:
		_phase += dt * (6.0 + speed * 1.8)
		var a := clampf(speed / 8.0, 0.35, 1.1)
		hf = sin(_phase) * 1.0 * a
		hb = -hf
		kf = -maxf(0.0, -cos(_phase)) * 1.5 * a - 0.1
		kb = -maxf(0.0, cos(_phase)) * 1.5 * a - 0.1
	elif not on_floor:
		hf = 1.1
		hb = 0.4
		kf = -1.4
		kb = -0.9
	hip_f.rotation.z = lerp_angle(hip_f.rotation.z, hf, w)
	hip_b.rotation.z = lerp_angle(hip_b.rotation.z, hb, w)
	knee_f.rotation.z = lerp_angle(knee_f.rotation.z, kf, w)
	knee_b.rotation.z = lerp_angle(knee_b.rotation.z, kb, w)


func swing_arms() -> void:
	shoulder_f.rotation.z = -hip_f.rotation.z * 0.8
	shoulder_b.rotation.z = -hip_b.rotation.z * 0.8


## Point an arm at a world-space hand position.
func point_arm(shoulder: Node3D, target: Vector3) -> void:
	var local := (shoulder.get_parent() as Node3D).to_local(target) - shoulder.position
	shoulder.rotation.z = atan2(local.y, local.x) + PI * 0.5
