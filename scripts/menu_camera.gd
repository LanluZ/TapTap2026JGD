extends Node3D
## 场景：scenes/menu.tscn 主菜单。作用：3D 背景——驱动球体（含描边壳）自转，相机轻微上下浮动；
## 按钮接线——开始游戏 → 关卡场景，退出 → 结束进程（设置按钮按确认不绑定）。

@onready var _pivot: Node3D = $SpherePivot
@onready var _camera: Camera3D = $Camera3D
@onready var _start_btn: Button = $UI/CenterContainer/MenuPanel/VBox/StartButton
@onready var _quit_btn: Button = $UI/CenterContainer/MenuPanel/VBox/QuitButton

var _time := 0.0

func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _process(delta: float) -> void:
	_time += delta
	_pivot.rotate_y(delta * 0.1)
	_camera.position.y = sin(_time * 0.8) * 0.1
