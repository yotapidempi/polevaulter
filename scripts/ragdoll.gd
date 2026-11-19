class_name Ragdoll
extends Node3D
## Jolt ragdoll built from the Rig part table: boxes joined by limited hinges,
## locked to the play plane so corpses tumble in 2D.

var bodies := {}


static func spawn(parent: Node, xform: Transform3D, facing: float, palette: Dictionary,
		hit_vel: Vector3, hit_point: Vector3, decapitate: bool) -> Ragdoll:
	var r := Ragdoll.new()
	parent.add_child(r)
	r._build(xform, facing, palette, hit_vel, hit_point, decapitate)
	return r


func _build(xform: Transform3D, facing: float, palette: Dictionary,
		hit_vel: Vector3, hit_point: Vector3, decapitate: bool) -> void:
	# Mirror by turning half a turn about Y (rigid bodies can't take negative scale).
	var root := Transform3D(Basis.IDENTITY if facing > 0.0 else Basis(Vector3.UP, PI), xform.origin)
	var phys := PhysicsMaterial.new()
	phys.friction = 0.8
	phys.bounce = 0.05

	var base_vel := hit_vel.limit_length(32.0) * 0.55
	var nearest: RigidBody3D
	var nearest_d := INF
	for part in Rig.PARTS:
		var def: Array = Rig.PARTS[part]
		var rb := RigidBody3D.new()
		rb.name = part
		rb.mass = def[2]
		rb.collision_layer = Game.LAYER_RAGDOLLS
		rb.collision_mask = Game.LAYER_WORLD | Game.LAYER_RAGDOLLS | Game.LAYER_PROPS
		rb.axis_lock_linear_z = true
		rb.axis_lock_angular_x = true
		rb.axis_lock_angular_y = true
		rb.continuous_cd = true
		rb.angular_damp = 0.8
		rb.physics_material_override = phys
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = def[0]
		shape.shape = box
		rb.add_child(shape)
		rb.add_child(Rig.part_mesh(part, palette))
		add_child(rb)
		rb.global_transform = root * Transform3D(Basis.IDENTITY, def[1])
		rb.linear_velocity = base_vel
		rb.angular_velocity = Vector3(0, 0, randf_range(-6.0, 6.0))
		bodies[part] = rb
		var dist := rb.global_position.distance_to(hit_point)
		if dist < nearest_d:
			nearest_d = dist
			nearest = rb

	for j in Rig.JOINTS:
		if decapitate and j[1] == "head":
			continue
		var joint := HingeJoint3D.new()
		add_child(joint)
		joint.global_transform = root * Transform3D(Basis.IDENTITY, j[2])
		joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(j[3]))
		joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(j[4]))
		joint.node_a = joint.get_path_to(bodies[j[0]])
		joint.node_b = joint.get_path_to(bodies[j[1]])

	if nearest:
		nearest.apply_impulse(hit_vel.limit_length(40.0) * nearest.mass * 0.5, hit_point - nearest.global_position)

	if decapitate:
		var head: RigidBody3D = bodies["head"]
		head.linear_velocity = base_vel * 1.4 + Vector3(0, 7, 0)
		head.angular_velocity = Vector3(0, 0, randf_range(-25.0, 25.0))
		_neck_fountain(bodies["torso"])


func _neck_fountain(torso: RigidBody3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 0.9
	p.local_coords = false
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.06
	box.material = Game.blood_mat
	p.mesh = box
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -24, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	torso.add_child(p)
	p.position = Vector3(0, 0.21, 0)
	p.emitting = true
	get_tree().create_timer(1.8, false).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false)
