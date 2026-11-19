extends Camera3D
## Side-on follow camera with velocity lookahead and trauma shake.

@export var target_path: NodePath
@export var distance := 17.0
@export var height := 1.2
@export var pitch_lift := 3.0
@export var lookahead := 0.35
@export var smooth := 6.0
@export var shake_strength := 0.7

var _target: Node3D
var _focus := Vector3.ZERO
var _zoom := 0.0
var _base_fov := 50.0


func _ready() -> void:
	_base_fov = fov
	_target = get_node(target_path)
	_focus = _target.global_position + Vector3(0, height, 0)
	_apply(Vector3.ZERO)


func _physics_process(dt: float) -> void:
	var vel := Vector3.ZERO
	if _target is CharacterBody3D:
		vel = (_target as CharacterBody3D).velocity
	var want := _target.global_position + Vector3(
		clampf(vel.x * lookahead, -4.5, 4.5),
		height + clampf(vel.y * 0.08, -1.5, 1.5), 0)
	_focus = _focus.lerp(want, 1.0 - exp(-smooth * dt))
	# Pull back a little at speed so launches show where you're headed.
	var extra := clampf((vel.length() - 8.0) * 0.35, 0.0, 5.0)
	_zoom = lerpf(_zoom, extra, 1.0 - exp(-2.0 * dt))
	var s := Game.trauma * Game.trauma * shake_strength
	_apply(Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * s)


## Impact punch-in, in real time so it plays during freeze-frames.
func _process(_dt: float) -> void:
	fov = _base_fov - Game.fov_kick


func snap() -> void:
	_focus = _target.global_position + Vector3(0, height, 0)
	_apply(Vector3.ZERO)
	reset_physics_interpolation()


func _apply(shake: Vector3) -> void:
	global_position = _focus + Vector3(0, pitch_lift, distance + _zoom) + shake
	look_at(_focus + shake * 0.5, Vector3.UP)
