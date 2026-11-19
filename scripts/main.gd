extends Node3D
## Test arena glue: restart, fall-out respawn, HUD.

@export var kill_y := -12.0

@onready var player: Player = $Player
@onready var cam = $Camera
@onready var kills_label: Label = $HUD/Kills


func _ready() -> void:
	Game.reset_level_state()
	$Sun.rotation_degrees = Vector3(-48, -35, 0)


func _physics_process(_dt: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if player.global_position.y < kill_y:
		player.respawn()
		cam.snap()


func _process(_dt: float) -> void:
	kills_label.text = "KILLS  %d" % Game.kills
