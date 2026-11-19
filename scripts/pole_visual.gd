class_name PoleVisual
extends Node3D
## Draws the pole as a chain of cylinders along a bent curve. Purely visual.

const SEGMENTS := 10
const RADIUS := 0.045

var _segs: Array[MeshInstance3D] = []
var _butt: MeshInstance3D
var _tip: MeshInstance3D


func _ready() -> void:
	top_level = true
	var shaft := CylinderMesh.new()
	shaft.top_radius = RADIUS
	shaft.bottom_radius = RADIUS
	shaft.height = 1.0
	shaft.radial_segments = 6
	shaft.rings = 0
	shaft.material = Game.mat(Color(0.98, 0.86, 0.3))
	for i in SEGMENTS:
		var m := MeshInstance3D.new()
		m.mesh = shaft
		add_child(m)
		_segs.append(m)
	var grip := CylinderMesh.new()
	grip.top_radius = RADIUS * 1.3
	grip.bottom_radius = RADIUS * 1.3
	grip.height = 1.0
	grip.radial_segments = 6
	grip.rings = 0
	grip.material = Game.mat(Color(0.1, 0.1, 0.12))
	_butt = MeshInstance3D.new()
	_butt.mesh = grip
	add_child(_butt)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.13, 0.22, 0.13)
	cap.material = Game.mat(Color(0.95, 0.15, 0.12))
	_tip = MeshInstance3D.new()
	_tip.mesh = cap
	add_child(_tip)


## hand: grip point. dir: unit direction toward the tip. length: hand-to-tip chord.
## bulge: sideways bow at the middle (metres). butt: how far the pole sticks out behind the hand.
func draw(hand: Vector3, dir: Vector3, length: float, bulge: float, butt: float) -> void:
	var perp := Vector3(-dir.y, dir.x, 0)
	if perp.y < 0.0:
		perp = -perp
	var tip := hand + dir * length
	var ctrl := hand + dir * (length * 0.5) + perp * (bulge * 2.0)
	var prev := hand
	for i in SEGMENTS:
		var t := float(i + 1) / SEGMENTS
		var p := hand * (1.0 - t) * (1.0 - t) + ctrl * 2.0 * (1.0 - t) * t + tip * t * t
		_place(_segs[i], prev, p)
		prev = p
	_place(_butt, hand - dir * butt, hand)
	var tip_dir := (tip - prev).normalized() if tip.distance_to(prev) > 0.001 else dir
	_place(_tip, tip - tip_dir * 0.22, tip)


func _place(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.0001:
		m.visible = false
		return
	m.visible = true
	var y := d / len
	var z := Vector3.BACK
	var x := y.cross(z).normalized()
	z = x.cross(y)
	if m == _tip:
		m.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	else:
		m.global_transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)
