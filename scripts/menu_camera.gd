extends Node3D
## 场景：scenes/menu.tscn 主菜单。作用：3D 背景——驱动球体（含描边壳）自转，相机轻微上下浮动；
## 按钮接线——开始游戏 → 地图选择面板（关卡列表实时读 levels.json）→ 关卡场景，
## 退出 → 结束进程（设置按钮按确认不绑定）。
## 选中的关卡 id 经 get_tree().root 的 meta "pending_level_id" 传给 scenes/main.tscn 的 Game 节点。

## 显示「每圈多少秒」用的敌人速度（史莱姆 90px/s，enemies.json）
const LAP_SPEED := 90.0

@onready var _pivot: Node3D = $SpherePivot
@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $UI
@onready var _start_btn: Button = $UI/CenterContainer/MenuPanel/VBox/StartButton
@onready var _quit_btn: Button = $UI/CenterContainer/MenuPanel/VBox/QuitButton

var _time := 0.0
var _picker: Control = null

func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)

func _on_start_pressed() -> void:
	if _picker != null:
		return
	var config = GameConfig.load_all()
	if config == null or config.levels.is_empty():
		_go(&"level_1") # 配置异常时退回默认关卡，错误已由加载器打印
		return
	_picker = _build_picker(config)
	_ui.add_child(_picker)


## 地图选择面板：关卡名 / 波数 / 每圈时长 / 建造格数全部从配置算，不手写。
func _build_picker(config) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "选择地图"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var ids: Array = config.levels.keys()
	ids.sort()
	for lid in ids:
		var lv: Dictionary = config.levels[lid]
		var cells := (lv["path_cells"] as Array).size()
		var lap := float(cells) * float(lv["cell_size"]) / LAP_SPEED
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 56)
		b.text = "%s ｜ %d 波 ｜ 每圈 %.1fs ｜ 建造 %d 格" % [
			String(lv["name"]), (lv["waves"] as Array).size(), lap,
			(lv["buildable_cells"] as Array).size(),
		]
		b.pressed.connect(_go.bind(lid))
		vb.add_child(b)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(420, 44)
	back.pressed.connect(_close_picker)
	vb.add_child(back)
	return overlay


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null


func _go(level_id: StringName) -> void:
	get_tree().root.set_meta("pending_level_id", level_id)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _process(delta: float) -> void:
	_time += delta
	_pivot.rotate_y(delta * 0.1)
	_camera.position.y = sin(_time * 0.8) * 0.1
