class_name Rig
extends Node3D
## Low-poly humanoid built from boxes. Origin at the feet, facing +X.
## The same part table drives the ragdoll, so corpses match the living body.

## name: [size, rest centre, mass, palette slot]
const PARTS := {
	"torso":   [Vector3(0.30, 0.62, 0.42), Vector3(0, 1.12, 0), 30.0, "shirt"],
	"head":    [Vector3(0.30, 0.30, 0.28), Vector3(0, 1.62, 0), 5.0, "skin"],
	"thigh_f": [Vector3(0.17, 0.40, 0.16), Vector3(0, 0.62, 0.11), 8.0, "pants"],
	"thigh_b": [Vector3(0.17, 0.40, 0.16), Vector3(0, 0.62, -0.11), 8.0, "pants"],
	"shin_f":  [Vector3(0.14, 0.42, 0.14), Vector3(0, 0.21, 0.11), 5.0, "boots"],
	"shin_b":  [Vector3(0.14, 0.42, 0.14), Vector3(0, 0.21, -0.11), 5.0, "boots"],
	"arm_f":   [Vector3(0.12, 0.62, 0.12), Vector3(0, 1.11, 0.27), 4.0, "sleeve"],
	"arm_b":   [Vector3(0.12, 0.62, 0.12), Vector3(0, 1.11, -0.27), 4.0, "sleeve"],
}

## [parent, child, pivot, lower deg, upper deg] (positive = rotating toward facing)
const JOINTS := [
	["torso", "head", Vector3(0, 1.46, 0), -35.0, 35.0],
	["torso", "thigh_f", Vector3(0, 0.82, 0.11), -40.0, 110.0],
	["torso", "thigh_b", Vector3(0, 0.82, -0.11), -40.0, 110.0],
	["thigh_f", "shin_f", Vector3(0, 0.42, 0.11), -130.0, 0.0],
	["thigh_b", "shin_b", Vector3(0, 0.42, -0.11), -130.0, 0.0],
	["torso", "arm_f", Vector3(0, 1.42, 0.27), -170.0, 170.0],
	["torso", "arm_b", Vector3(0, 1.42, -0.27), -170.0, 170.0],
]

const PLAYER_PALETTE := {
	"shirt": Color(0.12, 0.42, 0.95), "skin": Color(0.96, 0.74, 0.58),
	"pants": Color(0.14, 0.14, 0.22), "boots": Color(0.95, 0.95, 0.98),
	"sleeve": Color(0.96, 0.74, 0.58), "accent": Color(1.0, 0.45, 0.1),
}
const ENEMY_PALETTE := {
	"shirt": Color(0.78, 0.18, 0.16), "skin": Color(0.86, 0.66, 0.52),
	"pants": Color(0.32, 0.3, 0.3), "boots": Color(0.12, 0.1, 0.1),
	"sleeve": Color(0.78, 0.18, 0.16), "accent": Color(0.15, 0.12, 0.12),
}

var palette: Dictionary = ENEMY_PALETTE
var neck: Node3D
var hip_f: Node3D
var hip_b: Node3D
var knee_f: Node3D
var knee_b: Node3D
var shoulder_f: Node3D
var shoulder_b: Node3D
const YAW := 0.45  # turn toward the camera so the box people read as bodies

var facing := 0.0
var _phase := 0.0


static func part_mesh(part: String, pal: Dictionary) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = PARTS[part][0]
	b.material = Game.mat(pal[PARTS[part][3]])
	m.mesh = b
	return m


func _ready() -> void:
	var torso := part_mesh("torso", palette)
	torso.position = PARTS["torso"][1]
	add_child(torso)
	var belt := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.32, 0.08, 0.44)
	bb.material = Game.mat(palette["accent"])
	belt.mesh = bb
	belt.position = Vector3(0, 0.85, 0)
	add_child(belt)

	neck = _pivot(self, Vector3(0, 1.46, 0))
	var head := part_mesh("head", palette)
	head.position = Vector3(0, 0.16, 0)
	neck.add_child(head)
	var band := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.32, 0.07, 0.3)
	hb.material = Game.mat(palette["accent"])
	band.mesh = hb
	band.position = Vector3(0, 0.24, 0)
	neck.add_child(band)

	hip_f = _limb(self, Vector3(0, 0.82, 0.11), "thigh_f", 0.2)
	knee_f = _limb(hip_f, Vector3(0, -0.4, 0), "shin_f", 0.21)
	hip_b = _limb(self, Vector3(0, 0.82, -0.11), "thigh_b", 0.2)
	knee_b = _limb(hip_b, Vector3(0, -0.4, 0), "shin_b", 0.21)
	shoulder_f = _limb(self, Vector3(0, 1.42, 0.27), "arm_f", 0.31)
	shoulder_b = _limb(self, Vector3(0, 1.42, -0.27), "arm_b", 0.31)


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = at
	parent.add_child(p)
	return p


func _limb(parent: Node3D, at: Vector3, part: String, half: float) -> Node3D:
	var p := _pivot(parent, at)
	var m := part_mesh(part, palette)
	m.position = Vector3(0, -half, 0)
	p.add_child(m)
	return p


func face(f: float) -> void:
	if f == facing:
		return
	facing = f
	scale.x = f
	rotation.y = -YAW * f
	reset_physics_interpolation()


## Legs: run cycle on the ground, tuck in the air.
func animate_legs(speed: float, on_floor: bool, dt: float) -> void:
	var w := 1.0 - exp(-18.0 * dt)
	var hf := 0.0
	var hb := 0.0
	var kf := -0.05
	var kb := -0.05
	if on_floor and speed > 0.3:
		_phase += dt * (4.0 + speed * 1.3)
		var a := clampf(speed / 8.0, 0.3, 1.0)
		hf = sin(_phase) * 0.95 * a
		hb = -hf
		kf = -maxf(0.0, -cos(_phase)) * 1.4 * a - 0.1
		kb = -maxf(0.0, cos(_phase)) * 1.4 * a - 0.1
	elif not on_floor:
		hf = 0.9
		hb = 0.3
		kf = -1.3
		kb = -0.8
	hip_f.rotation.z = lerp_angle(hip_f.rotation.z, hf, w)
	hip_b.rotation.z = lerp_angle(hip_b.rotation.z, hb, w)
	knee_f.rotation.z = lerp_angle(knee_f.rotation.z, kf, w)
	knee_b.rotation.z = lerp_angle(knee_b.rotation.z, kb, w)


func swing_arms() -> void:
	shoulder_f.rotation.z = -hip_f.rotation.z * 0.8
	shoulder_b.rotation.z = -hip_b.rotation.z * 0.8


## Point an arm at a world-space hand position.
func point_arm(shoulder: Node3D, target: Vector3) -> void:
	var local := to_local(target) - shoulder.position
	shoulder.rotation.z = atan2(local.y, local.x) + PI * 0.5
