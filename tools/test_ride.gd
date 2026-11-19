extends SceneTree
## Headless-ish test ride: loads the arena, drives the player with fake stick input
## and prints telemetry. Scenario chosen with env SCEN (vault, pogo, strike, wall, shots).

var scen := "vault"
var main: Node
var player
var f := 0
var out_dir := "res://test_out/"


func _initialize() -> void:
	scen = OS.get_environment("SCEN") if OS.has_environment("SCEN") else "vault"
	out_dir = "res://test_out/%s/" % scen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	print("autoload present: ", root.get_node_or_null("Game") != null)
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child.call_deferred(main)
	set_deferred("current_scene", main)
	player = main.get_node("Player")


func aim(angle_deg: float, mag := 1.0) -> void:
	var a := deg_to_rad(angle_deg)
	var x := cos(a) * mag
	var y := sin(a) * mag
	_axis("aim_right", "aim_left", x)
	_axis("aim_up", "aim_down", y)


func aim_off() -> void:
	for a in ["aim_right", "aim_left", "aim_up", "aim_down"]:
		Input.action_release(a)


func _axis(pos: String, neg: String, v: float) -> void:
	Input.action_release(pos)
	Input.action_release(neg)
	if v > 0.01:
		Input.action_press(pos, v)
	elif v < -0.01:
		Input.action_press(neg, -v)


func tele(x: float, y := 0.0) -> void:
	player.global_position = Vector3(x, y, 0)
	player.velocity = Vector3.ZERO
	main.get_node("Camera").snap()


func log_state(tag := "") -> void:
	print("%4d %-6s pos(%6.2f,%5.2f) vel(%6.2f,%6.2f) planted=%s ang=%6.1f kills=%d %s" % [
		f, scen, player.global_position.x, player.global_position.y, player.velocity.x,
		player.velocity.y, player.planted, rad_to_deg(player.pole_angle), root.get_node("Game").kills, tag])


func shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_dir + name + ".png"))


func _physics_process(_dt: float) -> bool:
	f += 1
	match scen:
		"vault": _vault()
		"pogo": _pogo()
		"strike": _strike()
		"wall": _wall()
		"shots": _shots()
	return f > 400


func _vault() -> void:
	if f == 5: tele(20.0)
	if f == 6: Input.action_press("move_right")
	# t ~0.6 s in: plant ahead, then sweep the stick down and back.
	if f >= 40 and f < 70:
		var t := (f - 40) / 30.0
		aim(lerpf(-40.0, -150.0, t))
	if f == 70: aim_off()
	if OS.has_environment("KICK") and f == int(OS.get_environment("KICK")): Input.action_press("jump")
	if OS.has_environment("KICK") and f == int(OS.get_environment("KICK")) + 2: Input.action_release("jump")
	if f % 4 == 0 and f < 130: log_state()
	if f in [46, 56, 66, 80, 100]: shot("vault_%d" % f)


func _pogo() -> void:
	if f == 5: tele(-4.0)
	if f >= 10: aim(-90.0)
	if f % 5 == 0 and f < 250: log_state()


func _strike() -> void:
	if f == 5: tele(3.0)
	if f >= 30 and f < 34: aim(150.0)
	if f >= 34 and f < 44: aim(-20.0)
	if f == 44: aim_off()
	if f >= 30 and f < 70 and f % 2 == 0: log_state()
	if f in [36, 40, 50, 80, 120]: shot("strike_%d" % f)


func _wall() -> void:
	if f == 5: tele(28.5)
	if f >= 20: aim(0.0)
	if f % 4 == 0 and f < 120: log_state()


func _shots() -> void:
	if f == 5: tele(0.0)
	if f == 30: shot("start")
	if f == 40: tele(36.0)
	if f == 70: shot("crates")
	if f == 80: tele(90.0)
	if f == 110: shot("tower")
