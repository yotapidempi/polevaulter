class_name Enemy
extends CharacterBody3D
## Patrolling training dummy. Walks back and forth, turns at walls and ledges,
## turns into a Jolt ragdoll when struck, and respawns after a while.

@export var walk_speed := 1.6
@export var patrol := true
@export var respawn_time := 4.0
@export var start_facing := -1.0

var facing := -1.0
var dead := false
var rig: Rig
var _spawn: Transform3D
var _pause := 0.0


func _ready() -> void:
	_spawn = global_transform
	facing = start_facing
	rig = Rig.new()
	rig.palette = Rig.ENEMY_PALETTE
	add_child(rig)
	rig.face(facing)


func _physics_process(dt: float) -> void:
	if dead:
		return
	velocity.y -= 34.0 * dt
	if is_on_floor() and patrol:
		_pause -= dt
		var ahead := global_position + Vector3(facing * 0.55, 0.3, 0)
		var ground := _ray(ahead, ahead + Vector3(0, -1.0, 0))
		var blocked := is_on_wall() and get_wall_normal().x * facing < -0.5
		if ground.is_empty() or blocked:
			facing = -facing
			_pause = randf_range(0.3, 1.2)
		velocity.x = 0.0 if _pause > 0.0 else facing * walk_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * dt)
	move_and_slide()
	global_position.z = 0.0
	rig.face(facing)
	rig.animate_legs(absf(velocity.x), is_on_floor(), dt)
	rig.swing_arms()
	rig.lean = lerpf(rig.lean, velocity.x * facing * 0.05, 1.0 - exp(-10.0 * dt))
	rig.update_body(dt)


## Struck at `point` with relative velocity `hit_vel`.
func kill(point: Vector3, hit_vel: Vector3, decapitate: bool) -> void:
	if dead:
		return
	dead = true
	Game.kills += 1
	var corpse := Ragdoll.spawn(get_parent(), global_transform, rig.facing, rig.palette, hit_vel, point, decapitate)
	Game.register_corpse(corpse)
	Game.spawn_blood(point, hit_vel + Vector3.UP * 3.0, 70 if decapitate else 40)
	visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	get_tree().create_timer(respawn_time, false).timeout.connect(_respawn)


func _respawn() -> void:
	global_transform = _spawn
	facing = start_facing
	rig.face(facing)
	dead = false
	visible = true
	collision_layer = Game.LAYER_ENEMIES
	reset_physics_interpolation()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_WORLD | Game.LAYER_PROPS, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)
