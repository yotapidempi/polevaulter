class_name PoleVisual
extends Node3D
## Draws the pole as a chain of cylinders along a bent curve. Purely visual.

const SEGMENTS := 10
const RADIUS := 0.04
const SHAFT_COLOR := Color(0.98, 0.86, 0.3)

var _segs: Array[MeshInstance3D] = []
var _butt: MeshInstance3D
var _tip: MeshInstance3D
var _aim: MeshInstance3D
var _shaft_mat: StandardMaterial3D
var _charge := 0.0
var _aim_dot: MeshInstance3D


func _ready() -> void:
	top_level = true
	var shaft := CylinderMesh.new()
	shaft.top_radius = RADIUS
	shaft.bottom_radius = RADIUS
	shaft.height = 1.0
	shaft.radial_segments = 6
	shaft.rings = 0
	_shaft_mat = StandardMaterial3D.new()
	_shaft_mat.albedo_color = SHAFT_COLOR
	_shaft_mat.roughness = 0.6
	_shaft_mat.emission_enabled = true
	_shaft_mat.emission = Color(1.0, 0.55, 0.15)
	_shaft_mat.emission_energy_multiplier = 0.0
	shaft.material = _shaft_mat
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
	cap.size = Vector3(0.11, 0.18, 0.11)
	cap.material = Game.mat(Color(0.95, 0.15, 0.12))
	_tip = MeshInstance3D.new()
	_tip.mesh = cap
	add_child(_tip)

	var line := BoxMesh.new()
	line.size = Vector3(0.025, 1.0, 0.025)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.albedo_color = Color(1, 1, 1, 0.55)
	line.material = lm
	_aim = MeshInstance3D.new()
	_aim.mesh = line
	_aim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim.visible = false
	add_child(_aim)
	var dot := BoxMesh.new()
	dot.size = Vector3(0.09, 0.09, 0.09)
	dot.material = lm
	_aim_dot = MeshInstance3D.new()
	_aim_dot.mesh = dot
	_aim_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_dot.visible = false
	add_child(_aim_dot)


## Faint line from the hands toward where the stick points, ending in a small marker.
func draw_aim(hand: Vector3, dir: Vector3, length: float) -> void:
	_place(_aim, hand + dir * 0.3, hand + dir * length)
	_aim_dot.visible = true
	_aim_dot.global_position = hand + dir * length


## Glow with how loaded the pole is (0..1): this is exactly how strong a kick would be now.
func set_charge(c: float) -> void:
	_charge = lerpf(_charge, c, 0.5)
	_shaft_mat.emission_energy_multiplier = _charge * _charge * 2.5
	_shaft_mat.albedo_color = SHAFT_COLOR.lerp(Color(1.0, 0.98, 0.9), _charge)


func hide_aim() -> void:
	_aim.visible = false
	_aim_dot.visible = false


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
	_place(_tip, tip - tip_dir * 0.18, tip)


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
