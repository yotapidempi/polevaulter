class_name Player
extends CharacterBody3D
## Hand-tuned platformer controller with a spring-driven pole.
##
## Left stick runs, A jumps. The right stick sets the pole's target angle; the pole chases it
## through a stiff, slightly underdamped spring. When the tip meets a surface it plants:
## the pole then pushes back on the player like a compressed spring, and turning the stick
## while planted levers the body around the tip. Releasing the stick lets go; A while planted
## kicks off the pole. Anything the shaft sweeps through fast enough gets hit.

@export_group("Movement")
@export var run_speed := 8.5
## Exponential rates (1/s): the push is big when far from the target speed and tiny near it.
@export var accel_rate := 10.0
@export var turn_rate := 24.0
@export var stop_rate := 16.0
@export var air_rate := 6.0
## Air steering right after a launch, so launches keep their arc.
@export var launch_air_rate := 1.2
@export var launch_control_time := 0.45
## Above run speed on the ground, momentum bleeds off this slowly (m/s²).
@export var overspeed_friction := 4.0
@export var overspeed_stop := 16.0
@export var gravity := 34.0
@export var fall_gravity_mult := 1.35
## Near the top of a jump (|vy| below this) gravity eases off while A is held.
@export var apex_threshold := 3.0
@export var apex_gravity_mult := 0.45
@export var jump_velocity := 12.0
@export var jump_cut := 0.45
@export var coyote_time := 0.1
@export var jump_buffer := 0.12
@export var max_fall := 32.0

@export_group("Pole")
@export var pole_length := 2.2
## How much of the run into a plant turns into swing around the tip instead of compression.
@export var plant_redirect := 0.85
## 0 = the pole pushes along itself, 1 = straight out of the surface it's planted on.
@export_range(0.0, 1.0) var push_to_normal := 0.6
@export var aim_threshold := 0.35
## The pole is a weighted lever driven by limited muscle: stiffness pulls it toward the
## stick, but angular acceleration is capped, so big swings need a wind-up and carry through.
@export var aim_stiffness := 320.0
@export var aim_damping_ratio := 0.55
@export var rest_stiffness := 220.0
@export var max_swing_accel := 90.0   # rad/s², the muscle limit
@export var max_swing_speed := 32.0   # rad/s
@export var pole_gravity := 14.0      # rad/s² of sag pulling the tip down
## How much swinging the pole pushes your body around (pole mass / body mass).
@export var pole_mass_ratio := 0.0
@export_range(0.0, 1.0) var ground_reaction := 0.35
@export var plant_spring := 380.0
@export var plant_damping := 2.0
@export var max_preload := 0.4
@export var max_stretch := 0.04
@export var lever_strength := 120.0
@export var lever_damping := 6.0
@export var lever_max := 70.0
@export var pole_kick := 6.5
@export var max_kick_speed := 19.0
@export var kick_grace := 0.16
## Pole compression (m) that counts as fully loaded: full glow, full-power kick.
@export var full_bend := 0.3
@export var slip_angle_deg := 74.0

@export_group("Combat")
@export var strike_speed := 11.0
@export var decap_speed := 26.0
## Hit speed that counts as a full-force smash: longest freeze, biggest effects.
@export var full_power_speed := 34.0
@export var prop_hit_speed := 2.5
## After a mid-air kill, A within this window bounces you off it (timing-scaled like a kick).
@export var kill_kick_window := 0.2

const CHEST_HEIGHT := Rig.CHEST
const HAND_REACH := 0.22
const REST_ANGLE := 0.35  # starting carry angle: radians above horizontal, pointing behind
const BUTT := 0.25        # pole sticking out behind the hands when gripped normally

var facing := 1.0
var pole_angle := PI - REST_ANGLE
var pole_omega := 0.0
var planted := false
var anchor := Vector3.ZERO
var anchor_normal := Vector3.UP
var plant_rest := 0.0

var _plant_body: Object
var _needs_clear := false
var _aim_was := false
var _target_u := 0.0
var _last_raw := 0.0
var _aiming := false
var _stick_rate := 0.0
var _kick_window := 0.0
var _kick_window_len := 0.0
var _last_comp := 0.0
var _peak_comp := 0.0
var _release_charge := 0.0
var _muscle_alpha := 0.0
var last_kick_strength := 0.0
var _kick_dir := Vector2.UP
var _since_release := 1.0
var _jumping := false
var _coyote := 0.0
var _buffer := 0.0
var _spawn := Vector3.ZERO
var _strike_cd := {}
var _move := 0.0
var _launch_t := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _skid_t := 0.0
var _hold_angle := PI - REST_ANGLE
var _vis_len := 2.2
var _vis_bulge := 0.0
var _vis_butt := 0.25
var _strike_shape := CapsuleShape3D.new()

var rig: Rig
var pole: PoleVisual


func _ready() -> void:
	_spawn = global_position
	rig = Rig.new()
	rig.palette = Rig.PLAYER_PALETTE
	add_child(rig)
	pole = PoleVisual.new()
	add_child(pole)
	_strike_shape.radius = 0.14
	apply_preset(Game.feel_preset)


# --- Feel lab ---------------------------------------------------------------
## Swappable pole feels for comparing in play (D-pad up/down). Values not listed keep
## their Inspector setting. Once one wins, bake it into the defaults and drop the rest.
const PRESETS := [
	{"name": "Snappy", "note": "pole follows the stick almost instantly, no body push",
		"aim_stiffness": 1100.0, "aim_damping_ratio": 0.75, "max_swing_accel": 500.0,
		"max_swing_speed": 45.0, "pole_gravity": 0.0, "pole_mass_ratio": 0.0, "rest_stiffness": 400.0},
	{"name": "Firm", "note": "quick with a little weight, no body push",
		"aim_stiffness": 600.0, "aim_damping_ratio": 0.7, "max_swing_accel": 180.0,
		"max_swing_speed": 38.0, "pole_gravity": 6.0, "pole_mass_ratio": 0.0, "rest_stiffness": 300.0},
	{"name": "Weighted", "note": "wind-up and follow-through, no body push",
		"aim_stiffness": 320.0, "aim_damping_ratio": 0.55, "max_swing_accel": 90.0,
		"max_swing_speed": 32.0, "pole_gravity": 14.0, "pole_mass_ratio": 0.0, "rest_stiffness": 220.0},
	{"name": "Heavy", "note": "slow wind-up, swings drag your body around",
		"aim_stiffness": 240.0, "aim_damping_ratio": 0.45, "max_swing_accel": 65.0,
		"max_swing_speed": 30.0, "pole_gravity": 18.0, "pole_mass_ratio": 0.14, "rest_stiffness": 200.0},
]

var preset_name := ""
var preset_note := ""


func apply_preset(i: int) -> void:
	i = posmod(i, PRESETS.size())
	Game.feel_preset = i
	var p: Dictionary = PRESETS[i]
	for key in p:
		if key == "name":
			preset_name = p[key]
		elif key == "note":
			preset_note = p[key]
		else:
			set(key, p[key])


func respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	planted = false
	pole_omega = 0.0
	reset_physics_interpolation()
	pole.reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var move := Input.get_axis("move_left", "move_right")
	var aim := Input.get_vector("aim_left", "aim_right", "aim_down", "aim_up")
	var aiming := aim.length() > aim_threshold
	_aiming = aiming
	_move = move
	if Input.is_action_just_pressed("preset_next"):
		apply_preset(Game.feel_preset + 1)
		Sfx.play("tap_wood", global_position, -10.0, 1.2)
	elif Input.is_action_just_pressed("preset_prev"):
		apply_preset(Game.feel_preset - 1)
		Sfx.play("tap_wood", global_position, -10.0, 0.9)
	if absf(move) > 0.2:
		facing = signf(move)

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_land(_fall_speed)
	_was_on_floor = on_floor
	_coyote = coyote_time if on_floor else _coyote - dt
	_buffer = jump_buffer if Input.is_action_just_pressed("jump") else _buffer - dt
	_launch_t -= dt

	var v := Vector2(velocity.x, velocity.y)
	v = _run(v, move, on_floor, dt)

	# Gravity: shorter hop when A is let go early, floaty apex while it's held, heavier fall.
	if _jumping and v.y > 0.0 and not Input.is_action_pressed("jump"):
		v.y *= jump_cut
		_jumping = false
	if v.y <= 0.0:
		_jumping = false
	var g := gravity
	var floaty := Input.is_action_pressed("jump") or _launch_t > 0.0
	if not on_floor and absf(v.y) < apex_threshold and floaty:
		g *= apex_gravity_mult
	elif v.y < 0.0:
		g *= fall_gravity_mult
	v.y = maxf(v.y - g * dt, -max_fall)

	_kick_window -= dt
	_since_release += dt
	if planted:
		v = _planted_step(v, aim, aiming, dt)
	else:
		_free_step(aim, aiming, dt)
		v = _swing_reaction(v, on_floor, dt)
		if aiming:
			v = _try_plant(v)
		if not planted:
			_resolve_pole_overlap()
	# A while planted, or just after the pole lets go: kick off it.
	if Input.is_action_just_pressed("jump") and (planted or _kick_window > 0.0):
		var strength := _kick_strength()
		if planted:
			_release()
		v = _pole_kick(v, _kick_dir, strength)

	if not planted and _buffer > 0.0 and _coyote > 0.0:
		v.y = jump_velocity
		_jumping = true
		_buffer = 0.0
		_coyote = 0.0
		rig.punch(3.5)
		Game.spawn_dust(global_position, Vector3.UP, 8)
		Sfx.play("kick", global_position, -16.0, 1.7)

	velocity = Vector3(v.x, v.y, 0.0)
	if not on_floor:
		_fall_speed = maxf(0.0, -v.y)
	move_and_slide()
	if absf(global_position.z) > 0.0001:
		global_position.z = 0.0

	_check_strikes(dt)
	_update_visuals(dt)


func _approach(from: float, to: float, rate: float, dt: float) -> float:
	return lerpf(from, to, 1.0 - exp(-rate * dt))


func _run(v: Vector2, move: float, on_floor: bool, dt: float) -> Vector2:
	var target := move * run_speed
	var has_input := absf(move) > 0.1
	var control := 0.5 if planted else 1.0
	_skid_t -= dt
	if on_floor:
		var turning := has_input and v.x * move < -0.5
		if absf(v.x) > run_speed and not turning:
			# Carry launch speed: bleed it slowly while held, slide to a stop when let go.
			var f := overspeed_friction if has_input else overspeed_stop
			v.x = move_toward(v.x, signf(v.x) * run_speed if has_input else 0.0, f * dt)
		elif turning:
			v.x = _approach(v.x, target, turn_rate * control, dt)
			if absf(v.x) > 3.0 and _skid_t <= 0.0:
				_skid_t = 0.07
				Game.spawn_dust(global_position, Vector3(-signf(move), 0.6, 0), 3)
		elif has_input:
			v.x = _approach(v.x, target, accel_rate * control, dt)
		else:
			v.x = _approach(v.x, 0.0, stop_rate, dt)
	elif has_input and v.x * signf(move) < run_speed:
		# Air control never brakes a launch, it only steers below run speed,
		# and it's weak for a moment after a launch so the arc survives.
		var rate := launch_air_rate if _launch_t > 0.0 else air_rate
		v.x = _approach(v.x, target, rate * control, dt)
	return v


func _land(speed: float) -> void:
	if speed < 2.0:
		return
	rig.punch(-clampf(speed * 0.45, 1.0, 9.0))
	Game.spawn_dust(global_position, Vector3.UP, int(clampf(speed, 4.0, 18.0)))
	var s := clampf((speed - 2.0) / 22.0, 0.0, 1.0)
	Sfx.play("thud", global_position, lerpf(-16.0, -2.0, s), lerpf(1.2, 0.85, s))


# --- Pole -------------------------------------------------------------------

func _dir(angle: float) -> Vector3:
	return Vector3(cos(angle), sin(angle), 0.0)


func hand_pos() -> Vector3:
	return global_position + Vector3(0, CHEST_HEIGHT, 0) + _dir(pole_angle) * HAND_REACH


## Angle change from `from` to `to`: always the short way round, except on the ground,
## where a big swing that would go through your feet goes over your head instead.
func _swing_delta(from: float, to: float) -> float:
	var d1 := wrapf(to - from, -PI, PI)
	if absf(d1) < deg_to_rad(100.0) or not is_on_floor():
		return d1
	var d2 := d1 - signf(d1) * TAU
	if _passes_top(from, d1):
		return d1
	if _passes_top(from, d2):
		return d2
	return d1


func _passes_top(start: float, d: float) -> bool:
	var lo := minf(start, start + d)
	var hi := maxf(start, start + d)
	var k := ceilf((lo - PI * 0.5) / TAU)
	return PI * 0.5 + k * TAU <= hi


func _free_step(aim: Vector2, aiming: bool, dt: float) -> void:
	# The target is tracked unwrapped, so spinning the stick spins the pole.
	var target: float
	if aiming:
		var raw := atan2(aim.y, aim.x)
		if _aim_was:
			_target_u += wrapf(raw - _last_raw, -PI, PI)
		else:
			_target_u = pole_angle + _swing_delta(pole_angle, raw)
		_last_raw = raw
		# Never let the target run more than half a turn ahead of a lagging pole, or it
		# would chase it the long way round.
		_target_u = pole_angle + clampf(_target_u - pole_angle, -PI * 0.97, PI * 0.97)
		target = _target_u
	else:
		# Stick let go: hold the pole where it was. Turning around doesn't move it.
		if _aim_was:
			_hold_angle = pole_angle
		target = pole_angle + wrapf(_hold_angle - pole_angle, -PI, PI)
	_aim_was = aiming
	if absf(pole_angle) > TAU * 4.0:
		var shift := TAU * roundf(pole_angle / TAU)
		pole_angle -= shift
		_target_u -= shift

	var k := aim_stiffness if aiming else rest_stiffness
	var c := 2.0 * sqrt(k) * (aim_damping_ratio if aiming else 0.85)
	var err := target - pole_angle
	_muscle_alpha = clampf(k * err - c * pole_omega, -max_swing_accel, max_swing_accel)
	var alpha := _muscle_alpha - pole_gravity * cos(pole_angle)
	pole_omega = clampf(pole_omega + alpha * dt, -max_swing_speed, max_swing_speed)
	pole_angle += pole_omega * dt

	var hand := hand_pos()
	var u := _dir(pole_angle)
	var hit := _ray(hand, hand + u * pole_length, Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_ENEMIES)
	if hit.is_empty() or _since_release > 0.35:
		_needs_clear = false
	_vis_len = pole_length
	_vis_bulge = 0.0
	_vis_butt = BUTT


## A free pole can't pass through walls and floors: nudge it out of anything solid,
## knocking its swing back. Enemies don't block (they get hit instead).
func _resolve_pole_overlap() -> void:
	for i in 14:
		var hand := hand_pos()
		var u := _dir(pole_angle)
		var hit := _ray(hand, hand + u * pole_length, Game.LAYER_WORLD | Game.LAYER_PROPS)
		if hit.is_empty():
			return
		var n: Vector3 = hit.normal
		var s := 1.0 if Vector3(-u.y, u.x, 0).dot(n) >= 0.0 else -1.0
		if i == 0 and absf(pole_omega) > 5.0 and pole_omega * s < 0.0:
			var knock := clampf(absf(pole_omega) / 25.0, 0.0, 1.0)
			Sfx.play(Sfx.tap_for(hit.collider), hit.position, lerpf(-14.0, -2.0, knock), lerpf(1.15, 0.9, knock))
			Game.spawn_dust(hit.position, n, int(3 + knock * 8))
		pole_angle += s * deg_to_rad(4.0)
		if pole_omega * s < 0.0:
			pole_omega *= -0.15


func _try_plant(v: Vector2) -> Vector2:
	if _needs_clear:
		return v
	var hand := hand_pos()
	var u := _dir(pole_angle)
	var hit := _ray(hand, hand + u * pole_length, Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_ENEMIES)
	if hit.is_empty():
		return v
	var n: Vector3 = hit.normal
	if u.dot(-n) < cos(deg_to_rad(slip_angle_deg)):
		return v  # too glancing: the tip skids off
	var d := hand.distance_to(hit.position)
	if hit.collider is Enemy:
		# A swing fast enough to kill goes through; only slow contact pogos off them.
		var tip_speed := Vector3(v.x, v.y, 0) + Vector3(-u.y, u.x, 0) * pole_omega * d
		if (tip_speed - (hit.collider as Enemy).velocity).length() >= strike_speed:
			return v

	# Keep momentum: the part of the run that goes past the tip becomes swing around it,
	# so a running plant carries you up and over instead of stopping you dead. Hitting the
	# tip head-on (falling straight onto it) still compresses the pole for a bounce.
	var n2 := Vector2(-u.x, -u.y)
	var t2 := Vector2(-n2.y, n2.x)
	var vn := v.dot(n2)
	var vt := v.dot(t2)
	if vn < 0.0 and v.length() > 1.0:
		var k := plant_redirect * absf(vt) / v.length()
		var vt_new := (signf(vt) if absf(vt) > 0.01 else signf(t2.y)) * sqrt(vt * vt + k * vn * vn)
		v = t2 * vt_new + n2 * (vn * (1.0 - k))
	var tip_v := Vector3(v.x, v.y, 0) + Vector3(-u.y, u.x, 0) * pole_omega * d
	var into := tip_v.dot(-n)
	planted = true
	_peak_comp = 0.0
	_last_comp = 0.0
	anchor = Vector3(hit.position.x, hit.position.y, 0.0)
	anchor_normal = n
	plant_rest = minf(pole_length, d + max_preload * clampf(into / 6.0, 0.0, 1.0))
	_plant_body = hit.collider
	if _plant_body is RigidBody3D:
		var rb: RigidBody3D = _plant_body
		rb.apply_impulse(-n * maxf(into, 0.0) * rb.mass * 0.4, hit.position - rb.global_position)
	rig.punch(-2.0)
	var knock := clampf(into / 14.0, 0.0, 1.0)
	if hit.collider is Enemy:
		Sfx.play("thump", hit.position, lerpf(-16.0, -6.0, knock), 1.3)
	else:
		Sfx.play(Sfx.tap_for(hit.collider), hit.position, lerpf(-12.0, 0.0, knock), lerpf(1.1, 0.9, knock))
		Game.spawn_dust(hit.position, n, 3 + int(knock * 9.0))
	return v


func _release() -> void:
	if planted:
		var d := Vector2(hand_pos().x - anchor.x, hand_pos().y - anchor.y)
		_kick_dir = d.normalized() if d.length() > 0.01 else Vector2.UP
		_release_charge = clampf(_peak_comp / full_bend, 0.0, 1.0) * 0.85
		_open_kick_window(kick_grace)
		if not is_on_floor():
			_launch_t = launch_control_time
			rig.punch(2.5)
	planted = false
	_plant_body = null
	_needs_clear = true
	_since_release = 0.0


## Swinging a heavy pole pushes back on you: spinning it pulls you outward along the pole,
## and speeding it up shoves your body the other way. Full effect in the air, damped by
## your feet on the ground. A whiff drags you along with it.
func _swing_reaction(v: Vector2, on_floor: bool, dt: float) -> Vector2:
	var u := Vector2(cos(pole_angle), sin(pole_angle))
	var perp := Vector2(-u.y, u.x)
	var half := pole_length * 0.5
	var react := u * (pole_omega * pole_omega * half) - perp * (_muscle_alpha * half)
	react = (react * pole_mass_ratio).limit_length(45.0)
	if on_floor:
		react *= ground_reaction
		react.y = maxf(react.y, 0.0) * 0.5  # don't pin yourself into the floor
	return v + react * dt


func _open_kick_window(length: float) -> void:
	_kick_window = length
	_kick_window_len = length


## How much the pole is loaded right now, 0..1. The pole glows with exactly this, so what
## you see is what the kick gets: kick when it's brightest (deepest bend) for full power.
func pole_charge() -> float:
	if planted:
		return clampf(_last_comp / full_bend, 0.0, 1.0)
	if _kick_window > 0.0:
		# Just let go: the spring's energy is still in your legs, fading fast.
		return _release_charge * clampf(_kick_window / maxf(_kick_window_len, 0.001), 0.0, 1.0)
	return 0.0


func _kick_strength() -> float:
	return pole_kick * lerpf(0.6, 1.35, pole_charge())


## Kick off the pole (or out of a kill). The left stick steers it: push left/right to
## kick that way, leave it neutral to kick mostly up.
func _pole_kick(v: Vector2, base_dir: Vector2, strength: float) -> Vector2:
	_buffer = 0.0
	_kick_window = 0.0
	var steer := Vector2(_move * 1.2, 0.6) if absf(_move) > 0.2 else Vector2(0.0, 0.8)
	var dir := (base_dir + steer).normalized()
	var along := v.dot(dir)
	if along < 0.0:
		v -= dir * along  # kicking against your motion cancels it first
	v += dir * strength
	v.y = maxf(v.y, strength * 0.55)
	v = v.limit_length(maxf(max_kick_speed, (v - dir * strength).length()))
	_jumping = false
	_launch_t = launch_control_time
	var perfect := strength >= pole_kick * 1.15
	rig.punch(6.0 if perfect else 3.5)
	var s := clampf(strength / (pole_kick * 1.3), 0.0, 1.0)
	Sfx.play("kick", global_position, lerpf(-12.0, -2.0, s), lerpf(0.8, 1.1, s))
	if perfect:
		Game.add_trauma(0.2)
	Game.spawn_dust(hand_pos() - Vector3(base_dir.x, base_dir.y, 0) * 1.5,
		Vector3(base_dir.x, base_dir.y, 0), 18 if perfect else 6)
	last_kick_strength = strength
	return v


func _planted_step(v: Vector2, aim: Vector2, aiming: bool, dt: float) -> Vector2:
	if not aiming or not is_instance_valid(_plant_body):
		_release()
		_free_step(aim, aiming, dt)
		return v
	if _plant_body is CollisionObject3D and (_plant_body as CollisionObject3D).collision_layer == 0:
		_release()  # e.g. the enemy we stood on just died
		_free_step(aim, aiming, dt)
		return v

	var hand := hand_pos()
	var d := Vector2(hand.x - anchor.x, hand.y - anchor.y)
	var r := maxf(d.length(), 0.05)
	var n := d / r              # tip -> hand
	var u := -n                 # hand -> tip
	var cur := atan2(u.y, u.x)
	var target := atan2(aim.y, aim.x)
	var err := wrapf(target - cur, -PI, PI)

	var slipping := Vector3(u.x, u.y, 0).dot(-anchor_normal) < cos(deg_to_rad(slip_angle_deg))
	if r - plant_rest > max_stretch or absf(err) > 2.4 or slipping:
		_release()
		_free_step(aim, aiming, dt)
		return v

	var comp := plant_rest - r
	_last_comp = comp
	_peak_comp = maxf(_peak_comp, comp)
	# Push only: a planted tip can't pull you back.
	var a_r := plant_spring * comp - plant_damping * v.dot(n) if comp > 0.0 else 0.0
	var t := Vector2(-n.y, n.x)  # direction the hand moves when the pole turns counter-clockwise
	# PD lever: damp only the difference between how fast the pole turns and how fast the
	# stick turns, so sweeping the stick keeps momentum but a held stick settles.
	var stick_rate := wrapf(target - _last_raw, -PI, PI) / dt
	_stick_rate = lerpf(_stick_rate, stick_rate, 0.5)
	var pole_rate := v.dot(t) / r
	var a_t := lever_strength * err + lever_damping * (_stick_rate - pole_rate) * r
	a_t = clampf(a_t, -lever_max, lever_max)
	# The push leans toward the surface normal: off the floor it mostly lifts you rather
	# than shoving you back the way you came, so a forward plant doesn't brake the run.
	var surf := Vector2(anchor_normal.x, anchor_normal.y)
	var push := (n * (1.0 - push_to_normal) + surf * push_to_normal).normalized()
	v += (push * a_r + t * a_t) * dt

	pole_omega = wrapf(cur - pole_angle, -PI, PI) / dt
	pole_angle = cur
	_target_u = cur + err
	_last_raw = target
	_aim_was = true
	# Constant pole length: the hands gripped `plant_rest` from the tip, the rest sticks out
	# behind them, and compression shows as a bow whose arc keeps that length.
	_vis_len = r
	_vis_bulge = sqrt(maxf(0.0, 3.0 * r * (plant_rest - r) / 8.0))
	_vis_butt = BUTT + (pole_length - plant_rest)
	return v


# --- Combat -----------------------------------------------------------------

func _check_strikes(dt: float) -> void:
	for id in _strike_cd.keys():
		_strike_cd[id] -= dt
		if _strike_cd[id] <= 0.0:
			_strike_cd.erase(id)
	if not _aiming:
		return  # a carried pole doesn't hurt anyone

	var hand := hand_pos()
	var u := _dir(pole_angle)
	var len := maxf(_vis_len, 0.3)
	_strike_shape.height = len + _strike_shape.radius * 2.0
	var y := u
	var z := Vector3.BACK
	var x := y.cross(z)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _strike_shape
	q.transform = Transform3D(Basis(x, y, z), hand + u * (len * 0.5))
	q.collision_mask = Game.LAYER_ENEMIES | Game.LAYER_RAGDOLLS | Game.LAYER_PROPS
	q.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 24)

	for h in hits:
		var col: Object = h.collider
		if col == null or _strike_cd.has(col.get_instance_id()):
			continue
		var centre: Vector3 = (col as Node3D).global_position
		if col is Enemy:
			centre += Vector3(0, CHEST_HEIGHT, 0)
		var s := clampf((centre - hand).dot(u), 0.0, len)
		var point := hand + u * s
		var pv := velocity + Vector3(-u.y, u.x, 0) * pole_omega * s

		if col is Enemy:
			var enemy: Enemy = col
			var rel := pv - enemy.velocity
			var speed := rel.length()
			if speed >= strike_speed and not enemy.dead:
				_strike_cd[col.get_instance_id()] = 0.3
				var power := impact_power(speed)
				enemy.kill(point, rel, speed >= decap_speed, power)
				pole_omega *= lerpf(0.7, 0.4, power)  # harder hits cost more swing
				Game.impact(point, rel, power)
				if not is_on_floor() and not planted:
					# Air kill: press A right after the hit to bounce off it. The window is
					# short, but it doesn't tick during the freeze-frame, which gives you the beat.
					_kick_dir = Vector2.UP
					_release_charge = 0.8
					_open_kick_window(kill_kick_window)
		elif col is RigidBody3D:
			var rb: RigidBody3D = col
			var rel := pv - rb.linear_velocity
			var spd := rel.length()
			if spd < prop_hit_speed:
				continue
			# Corpses and crates just get nudged: no freeze or impact effects, and a whole
			# corpse counts as one thing, so sweeping through its limbs makes one soft sound.
			var flesh := (rb.collision_layer & Game.LAYER_RAGDOLLS) != 0
			var owner_id := rb.get_parent().get_instance_id() if flesh else col.get_instance_id()
			rb.apply_impulse(rel * rb.mass * (0.3 if flesh else 0.45), point - rb.global_position)
			_strike_cd[col.get_instance_id()] = 0.15
			if _strike_cd.has(owner_id) and owner_id != col.get_instance_id():
				continue
			_strike_cd[owner_id] = 0.4
			var loud := clampf((spd - prop_hit_speed) / 20.0, 0.0, 1.0)
			if flesh:
				Sfx.play("thump", point, lerpf(-22.0, -12.0, loud), 1.25)
				if spd > strike_speed * 1.5:
					Game.spawn_blood(point, rel, 6)
			else:
				Sfx.play("tap_wood", point, lerpf(-16.0, -4.0, loud), lerpf(1.1, 0.9, loud))


## 0 at the kill threshold, 1 for a full-force smash.
func impact_power(speed: float) -> float:
	return clampf((speed - strike_speed) / (full_power_speed - strike_speed), 0.0, 1.0)


# --- Visuals ----------------------------------------------------------------

func _update_visuals(dt: float) -> void:
	rig.face(facing)
	var on_floor := is_on_floor()
	rig.animate_legs(absf(velocity.x), on_floor, dt)
	# Lean into speed on the ground; in the air, pitch with the arc.
	var fwd := velocity.x * facing
	var want_lean := clampf(fwd / run_speed, -1.0, 1.8) * 0.2
	if not on_floor:
		want_lean = clampf(fwd / run_speed, -1.0, 1.5) * 0.12 - clampf(velocity.y / 20.0, -0.3, 0.3)
	rig.lean = lerpf(rig.lean, want_lean, 1.0 - exp(-12.0 * dt))
	rig.update_body(dt)
	var hand := hand_pos()
	var u := _dir(pole_angle)
	rig.point_arm(rig.shoulder_f, hand)
	rig.point_arm(rig.shoulder_b, hand - u * 0.22)
	pole.draw(hand, u, _vis_len, _vis_bulge, _vis_butt)
	pole.set_charge(pole_charge())
	# Faint line where the stick points, so a lagging pole still reads clearly.
	if _aiming and not planted:
		pole.draw_aim(hand, _dir(_last_raw), pole_length)
	else:
		pole.hide_aim()
	var tip_speed := 0.0 if planted else absf(pole_omega) * pole_length
	Sfx.whoosh(tip_speed, hand + u * pole_length)


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)
