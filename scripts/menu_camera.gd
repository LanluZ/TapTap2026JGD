extends Node2D
## 场景：scenes/menu.tscn 主菜单。作用：Logo 浮动、按钮接线（纯 2D，无 3D）。
## Logo 缓慢上下浮动 + 轻微摇摆（光泽/破损在 shaders/logo_gloss_dissolve.gdshader）；
## 按钮接线——开始游戏 → 地图选择面板（关卡列表实时读 levels.json）→ 关卡场景，
## 退出 → 结束进程（设置按钮按确认不绑定）。
## 选中的关卡 id 经 get_tree().root 的 meta "pending_level_id" 传给 scenes/main.tscn 的 Game 节点。

## 显示「每圈多少秒」用的敌人速度（史莱姆 90px/s，enemies.json）
const LAP_SPEED := 90.0

## 选关界面预制体：轮播预览三张地图（res://art/maps/），选完发 level_chosen。
const LEVEL_SELECT := preload("res://scenes/ui/level_select.tscn")

## 设置界面预制体：两条音量滑块（背景音乐 / 音效），首次点「设置」时懒加载。
const MENU_SETTINGS := preload("res://scenes/ui/menu_settings.tscn")

## Logo 缓慢浮动：上下 10px + 轻微摇摆（±2.5°），两个周期错开，避免看起来像机械升降。
## 光泽扫过与破损消融在 shaders/logo_gloss_dissolve.gdshader 里，这里只动位置/角度。
const LOGO_BOB_PX := 10
const LOGO_BOB_SPEED := 0.7
const LOGO_ROCK_DEG := 1.5
const LOGO_ROCK_SPEED := 0.62

## 背景三层视差：远景(背景1)/中景(背景2)/前景(背景3) 对鼠标反向位移，factor 越大移动越多。
## 鼠标位移反向是为了像「转头看」：指针往右 → 背景往左。
## PARALLAX_MAX 是前景层在指针贴边时的位移（px），每层实际位移 = PARALLAX_MAX * factor + 摇摆。
## 各层位移必须小于贴图超出视口的余量（见 tests/menu_parallax_test.gd），否则会露出底边。
const PARALLAX_MAX := Vector2(24.0, 10.0)
const PARALLAX_SMOOTH := 0.12 # 平滑时间常数（秒），越小越跟手
const PARALLAX_LAYERS := [
	{"node": "背景1", "factor": 0.3, "sway_px": 2.0, "sway_speed": 0.55, "sway_phase": 0.0},
	{"node": "背景2", "factor": 0.65, "sway_px": 4.0, "sway_speed": 0.47, "sway_phase": 1.7},
	{"node": "背景3", "factor": 1.0, "sway_px": 5.0, "sway_speed": 0.41, "sway_phase": 3.1},
]

@onready var _ui: Control = $UI
@onready var _logo: Sprite2D = $UI.get_node_or_null("Logo") as Sprite2D
@onready var _start_btn: Button = $UI/CenterContainer/MenuPanel/VBox/StartButton
@onready var _settings_btn: Button = $UI/CenterContainer/MenuPanel/VBox/SettingsButton
@onready var _quit_btn: Button = $UI/CenterContainer/MenuPanel/VBox/QuitButton

var _time := 0.0
var _picker: Node = null
var _settings: Control = null
var _logo_base := Vector2.ZERO
var _bg_nodes: Array[Sprite2D] = []
var _bg_base: Array[Vector2] = []
var _parallax := Vector2.ZERO

func _ready() -> void:
	Bgm.play_title() # 菜单/选关用 title 曲（关卡内由 game.gd 切战斗曲）
	_start_btn.pressed.connect(_on_start_pressed)
	_settings_btn.pressed.connect(_on_settings_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	if _logo != null:
		_logo_base = _logo.position
	for cfg in PARALLAX_LAYERS:
		var sp := _ui.get_node_or_null(NodePath(String(cfg["node"]))) as Sprite2D
		_bg_nodes.append(sp)
		_bg_base.append(sp.position if sp != null else Vector2.ZERO)

func _on_start_pressed() -> void:
	if _picker != null:
		return
	var config = GameConfig.load_all()
	if config == null or config.levels.is_empty():
		_go(&"level_1") # 配置异常时退回默认关卡，错误已由加载器打印
		return
	_picker = LEVEL_SELECT.instantiate()
	_ui.add_child(_picker)
	_picker.level_chosen.connect(_go)
	_picker.closed.connect(_close_picker)
	_picker.setup(config)


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null


## 设置界面：首次点「设置」时实例化到 UI 层（全屏遮罩 + 居中面板），之后复用。
func _on_settings_pressed() -> void:
	if _settings == null:
		_settings = MENU_SETTINGS.instantiate()
		_ui.add_child(_settings)
	_settings.open()


func _go(level_id: StringName) -> void:
	get_tree().root.set_meta("pending_level_id", level_id)
	SceneTransition.change_scene("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _process(delta: float) -> void:
	_time += delta
	if _logo != null:
		_logo.position = _logo_base + Vector2(0.0, sin(_time * LOGO_BOB_SPEED) * LOGO_BOB_PX)
		_logo.rotation_degrees = sin(_time * LOGO_ROCK_SPEED + 1.1) * LOGO_ROCK_DEG
	_update_parallax(delta)


## 指针相对视口中心归一化到 [-1,1]，平滑后反向量乘各层 factor，再叠一层各自缓慢的左右摇摆。
func _update_parallax(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var target := Vector2.ZERO
	if vp.x > 0.0 and vp.y > 0.0:
		target = (get_viewport().get_mouse_position() / vp * 2.0 - Vector2.ONE).clamp(
			Vector2(-1.0, -1.0), Vector2(1.0, 1.0)
		)
	_parallax = _parallax.lerp(target, 1.0 - exp(-delta / PARALLAX_SMOOTH))
	for i in _bg_nodes.size():
		var sp := _bg_nodes[i]
		if sp == null:
			continue
		var cfg: Dictionary = PARALLAX_LAYERS[i]
		var off := -PARALLAX_MAX * float(cfg["factor"]) * _parallax
		off.x += sin(_time * float(cfg["sway_speed"]) + float(cfg["sway_phase"])) * float(cfg["sway_px"])
		sp.position = _bg_base[i] + off
