extends Control
## 场景：scenes/ui/level_select.tscn。作用：选关轮播（左中右三张地图预览 + 左右箭头 + 返回）。
## 对外契约：
##   setup(config)                 注入 GameConfig，按 levels 顺序渲染
##   signal level_chosen(level_id) 点击中央卡 / Enter
##   signal closed                 返回按钮 / ESC
## 预览图取 art/maps/<关卡序号>.png（序号 = levels.json 里的顺序），缺图时留空底。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const MAP_DIR := "res://art/maps/"
## 三张卡在轮播里的固定槽位：左 / 中 / 右
const SLOT_OFFSETS := [-1, 0, 1]

const POS_CENTER := Vector2(290.0, 60.0)
const SIZE_CENTER := Vector2(620.0, 349.0)
const POS_SIDE_LEFT := Vector2(-150.0, 96.0)
const POS_SIDE_RIGHT := Vector2(854.0, 96.0)
const SIZE_SIDE := Vector2(496.0, 279.0)

## 侧卡压暗，让中央卡成为唯一视觉焦点
const DIM_MODULATE := Color(0.62, 0.62, 0.72, 1.0)
const HOVER_MODULATE := Color(0.82, 0.82, 0.9, 1.0)

signal level_chosen(level_id: StringName)
signal closed

@onready var _cards: Array[PanelContainer] = [
	$Center/Panel/VBox/Row/Stage/CardL,
	$Center/Panel/VBox/Row/Stage/CardC,
	$Center/Panel/VBox/Row/Stage/CardR,
]
@onready var _arrow_l: Button = $Center/Panel/VBox/Row/ArrowLeft
@onready var _arrow_r: Button = $Center/Panel/VBox/Row/ArrowRight
@onready var _back: Button = $Center/Panel/VBox/BackButton

var _ids: Array[StringName] = []
var _names: Dictionary = {}
var _index := 0
var _side_style: StyleBox
var _center_style: StyleBox
var _tex_cache: Dictionary = {}
var _fade: Tween


func _ready() -> void:
	_side_style = _cards[1].get_theme_stylebox("panel")
	_center_style = _make_center_style()
	_arrow_l.pressed.connect(_step.bind(-1))
	_arrow_r.pressed.connect(_step.bind(1))
	_back.pressed.connect(_on_back)
	for k in _cards.size():
		_cards[k].gui_input.connect(_on_card_input.bind(k))
		_cards[k].mouse_entered.connect(_on_card_hover.bind(k, true))
		_cards[k].mouse_exited.connect(_on_card_hover.bind(k, false))
	_refresh(false)


## 注入关卡配置并按 levels 顺序渲染；重复调用只换数据不重建节点。
func setup(config) -> void:
	if not is_node_ready():
		await ready
	_ids.clear()
	_names.clear()
	var ids: Array = config.levels.keys()
	# StringName 的 < 是内部指针序，sort() 排出来是乱序 → 按 id 字符串排
	ids.sort_custom(func(a, b): return str(a) < str(b))
	for id in ids:
		_ids.append(StringName(id))
		_names[StringName(id)] = str(config.get_level(id).get("name", id))
	_index = 0
	var multi := _ids.size() > 1
	_arrow_l.visible = multi
	_arrow_r.visible = multi
	_refresh(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_step(1)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		_activate()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		_on_back()
		accept_event()


## 按「当前 index ± 槽位」重铺三张卡的内容与几何。animate=true 时中央卡淡入。
func _refresh(animate: bool) -> void:
	for k in _cards.size():
		var card: PanelContainer = _cards[k]
		if _ids.is_empty():
			card.visible = false
			continue
		card.visible = true
		var off: int = SLOT_OFFSETS[k]
		var idx := _wrap(_index + off)
		var id: StringName = _ids[idx]
		(card.get_node("VBox/Shot") as TextureRect).texture = _texture_at(idx)
		var label := card.get_node("VBox/Name") as Label
		label.text = str(_names.get(id, String(id)))
		var centered := off == 0
		label.add_theme_font_size_override("font_size", 24 if centered else 18)
		card.size = SIZE_CENTER if centered else SIZE_SIDE
		card.position = POS_CENTER if centered else (POS_SIDE_LEFT if off < 0 else POS_SIDE_RIGHT)
		card.add_theme_stylebox_override("panel", _center_style if centered else _side_style)
		card.modulate = Color(1, 1, 1, 1) if centered else DIM_MODULATE
	if animate and not _ids.is_empty():
		_play_center_fade()


func _play_center_fade() -> void:
	var center := _cards[1]
	if _fade != null and _fade.is_valid():
		_fade.kill()
	center.modulate.a = 0.35
	_fade = create_tween()
	_fade.tween_property(center, "modulate:a", 1.0, 0.18)


func _step(dir: int) -> void:
	if _ids.size() < 2:
		return
	_index = _wrap(_index + dir)
	_refresh(true)


func _activate() -> void:
	if _ids.is_empty():
		return
	level_chosen.emit(_ids[_index])


func _on_back() -> void:
	closed.emit()


## 点侧卡 = 翻到那一张；点中央卡 = 开始。
func _on_card_input(event: InputEvent, slot: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var off: int = SLOT_OFFSETS[slot]
	if off == 0:
		_activate()
	else:
		_step(off)


func _on_card_hover(slot: int, entering: bool) -> void:
	if slot == 1:
		return
	_cards[slot].modulate = HOVER_MODULATE if entering else DIM_MODULATE


func _wrap(i: int) -> int:
	var n := _ids.size()
	return ((i % n) + n) % n


## 预览图按关卡序号取，缺图返回 null（TextureRect 留空底，不伪造素材）
func _texture_at(idx: int) -> Texture2D:
	if _tex_cache.has(idx):
		return _tex_cache[idx]
	var path := MAP_DIR + str(idx) + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[idx] = tex
	return tex


func _make_center_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.COLOR_PANEL_DARK
	sb.border_color = UiStyle.COLOR_ACCENT
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6.0)
	return sb
