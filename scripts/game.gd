extends Node
## Global juice and bookkeeping: hitstop, camera shake, blood, corpses, kill count.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMIES := 4
const LAYER_RAGDOLLS := 8
const LAYER_PROPS := 16

const MAX_SPLATS := 260
const MAX_CORPSES := 14

var trauma := 0.0
var kills := 0

var blood_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var fov_kick := 0.0
var feel_preset := 2  # index into Player.PRESETS; kept across restarts
var _mats := {}
var _splats: Array[Node3D] = []
var _corpses: Array[Node] = []
var _hitstop_until := 0
var _last_ticks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	blood_mat = StandardMaterial3D.new()
	blood_mat.albedo_color = Color(0.6, 0.02, 0.05)
	blood_mat.roughness = 0.2
	blood_mat.metallic_specular = 0.8
	_last_ticks = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_dt := (now - _last_ticks) / 1000.0
	_last_ticks = now
	if Engine.time_scale < 1.0 and now >= _hitstop_until:
		Engine.time_scale = 1.0
	trauma = maxf(0.0, trauma - real_dt * 1.8)
	fov_kick *= exp(-real_dt * 9.0)


## Flat-coloured material, cached per colour.
func mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_mats[c] = m
	return m


## Freeze-frame for impact. Real-time duration, independent of the slowed clock.
func hitstop(seconds: float, scale := 0.02) -> void:
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = scale


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## One hit, scaled by `power` (0 = barely over the kill threshold, 1 = full-force smash):
## freeze-frame, shake, camera punch, a ring and burst lines at the contact point.
## The freeze grows faster than linearly, so big hits really stop the world.
func impact(at: Vector3, dir: Vector3, power: float) -> void:
	power = clampf(power, 0.0, 1.0)
	hitstop(lerpf(0.02, 0.17, pow(power, 1.3)))
	add_trauma(0.12 + 0.55 * power)
	fov_kick = maxf(fov_kick, 1.5 + 6.0 * power)
	_ring(at, 0.5 + 1.8 * power, 0.12 + 0.12 * power)
	_burst(at, dir, 5 + int(power * 7.0), 0.5 + 1.6 * power, 0.1 + 0.1 * power)


func _effect_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 10
	return m


func _tween() -> Tween:
	var tw := create_tween()
	tw.set_ignore_time_scale(true)  # effects play out during the freeze-frame
	return tw


## Expanding flat ring facing the camera.
func _ring(at: Vector3, size: float, seconds: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 18
	torus.ring_segments = 3
	var mat := _effect_mat(Color(1, 1, 0.95, 0.95))
	torus.material = mat
	m.mesh = torus
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(m)
	m.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * 0.15), at + Vector3(0, 0, 0.6))
	var tw := _tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(size, 0.3, size), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tw.tween_property(mat, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(m.queue_free)


## Comic-style impact lines shooting out from the contact point, biased along the hit.
func _burst(at: Vector3, dir: Vector3, count: int, length: float, seconds: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var base := atan2(dir.y, dir.x) if dir.length_squared() > 0.01 else 0.0
	for i in count:
		var ang := base + randf_range(-1.3, 1.3) if i < count * 0.6 else randf() * TAU
		var d := Vector3(cos(ang), sin(ang), 0)
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, 1.0, 0.05)
		var mat := _effect_mat(Color(1, 0.95, 0.6, 1) if i % 2 == 0 else Color(1, 1, 1, 1))
		box.material = mat
		m.mesh = box
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(m)
		var x := d.cross(Vector3.BACK).normalized()
		var len := length * randf_range(0.5, 1.0)
		var start := at + d * 0.15 + Vector3(0, 0, 0.6)
		m.global_transform = Transform3D(Basis(x, d * 0.01, Vector3.BACK), start)
		var tw := _tween()
		tw.set_parallel(true)
		var end_basis := Basis(x, d * len, Vector3.BACK)
		tw.tween_property(m, "transform", Transform3D(end_basis, start + d * len * 0.6), seconds) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		tw.tween_property(mat, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(m.queue_free)


## Flash every mesh under `root` white for a moment (real time, so it shows during the freeze).
func flash(root: Node, seconds := 0.07) -> void:
	if _flash_mat == null:
		_flash_mat = _effect_mat(Color(1, 1, 1, 1))
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_flash_mat.no_depth_test = false
	var meshes: Array[GeometryInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n)
		(n as GeometryInstance3D).material_override = _flash_mat
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
		for g in meshes:
			if is_instance_valid(g):
				g.material_override = null)


func reset_level_state() -> void:
	Engine.time_scale = 1.0
	trauma = 0.0
	fov_kick = 0.0
	kills = 0
	_splats.clear()
	_corpses.clear()


func register_corpse(node: Node) -> void:
	_corpses = _corpses.filter(func(n): return is_instance_valid(n))
	_corpses.append(node)
	while _corpses.size() > MAX_CORPSES:
		var old: Node = _corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A burst of blood droplets, plus splats painted onto nearby surfaces.
func spawn_blood(pos: Vector3, dir: Vector3, amount: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	dir = dir.normalized()

	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = 1.3
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.07
	box.material = blood_mat
	p.mesh = box
	p.direction = dir
	p.spread = 38.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -24, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.7
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

	var space := scene.get_viewport().world_3d.direct_space_state
	for i in maxi(2, amount / 7):
		var d := (dir + Vector3(randf_range(-0.8, 0.8), randf_range(-1.1, 0.3), randf_range(-0.6, 0.6))).normalized()
		var q := PhysicsRayQueryParameters3D.create(pos, pos + d * 6.0, LAYER_WORLD | LAYER_PROPS)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var delay := pos.distance_to(hit.position) / 14.0
		get_tree().create_timer(delay, false).timeout.connect(
			_add_splat.bind(hit.position, hit.normal, randf_range(0.1, 0.38), hit.collider))


## Puff of chunky dust for landings, jumps, skids and kicks.
func spawn_dust(pos: Vector3, dir: Vector3, amount: int) -> void:
	var scene := get_tree().current_scene
	if scene == null or amount <= 0:
		return
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.albedo_color = Color(0.95, 0.9, 0.82)
		_dust_mat.roughness = 1.0
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.45
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.12
	box.material = _dust_mat
	p.mesh = box
	p.direction = dir.normalized() if dir.length_squared() > 0.0 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, 2.0, 0)
	p.damping_min = 4.0
	p.damping_max = 6.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(p)
	p.global_position = pos + Vector3(0, 0.05, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _add_splat(at: Vector3, normal: Vector3, radius: float, collider: Object) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var parent: Node = scene
	if collider is RigidBody3D and is_instance_valid(collider):
		parent = collider
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.015
	cyl.radial_segments = 7
	cyl.rings = 0
	cyl.material = blood_mat
	m.mesh = cyl
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	var y := normal.normalized()
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	m.global_transform = Transform3D(Basis(x, y, z).rotated(y, randf() * TAU), at + y * (0.01 + randf() * 0.01))
	_splats.append(m)
	while _splats.size() > MAX_SPLATS:
		var old: Node3D = _splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()
