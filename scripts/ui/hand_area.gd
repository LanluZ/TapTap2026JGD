extends HBoxContainer
## 手牌区：按手牌上限生成槽位（空槽占位），点击卡牌进入选中 → 放置预览状态。
## 再次点击已选卡牌 = 取消选中（发 selection_cleared，由根节点转成 placement_cancelled）。

signal card_selected(card: Dictionary)
signal selection_cleared()
signal card_right_clicked(card: Dictionary) # 右键卡片：查看 DNA 序列（DNA 系统）

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiCardFace = preload("res://scripts/ui/card_face.gd")

const CARD_MIN_SIZE := Vector2(100, 120)
const EMPTY_TEXT := "空"
const MIN_HAND_MAX := 1
const MAX_HAND_MAX := 12

var _cards: Array = []
var _hand_max := 7
var _selected := -1


func _ready() -> void:
	_rebuild()


## 整副手牌注入：元素须为卡牌 Dictionary（非法项跳过并警告）
func set_hand(cards: Array) -> void:
	_cards.clear()
	for card in cards:
		if card is Dictionary:
			_cards.append(card)
		else:
			push_warning("[手牌] 跳过非法卡牌项：%s" % str(card))
	if _selected >= _cards.size():
		_selected = -1
	_rebuild()


## 手牌上限（槽位数量）
func set_hand_max(hand_max: int) -> void:
	_hand_max = clampi(hand_max, MIN_HAND_MAX, MAX_HAND_MAX)
	_rebuild()


func get_hand_max() -> int:
	return _hand_max


func get_cards() -> Array:
	return _cards.duplicate()


func get_card_count() -> int:
	return _cards.size()


func get_selected_index() -> int:
	return _selected


func get_selected_card() -> Dictionary:
	if _selected < 0 or _selected >= _cards.size():
		return {}
	return _cards[_selected]


## 取消选中；notify=true 时广播 selection_cleared（无选中则不发）
func clear_selection(notify: bool = true) -> void:
	if _selected < 0:
		return
	_selected = -1
	_apply_styles()
	if notify:
		selection_cleared.emit()


func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	if index == _selected:
		clear_selection(true)
		return
	_selected = index
	_apply_styles()
	card_selected.emit(_cards[index])


## 右键卡片 = 查看 DNA 序列（不进入放置/选中状态）。
func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if index >= 0 and index < _cards.size():
			card_right_clicked.emit(_cards[index])


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	var total := maxi(_hand_max, _cards.size())
	for index in total:
		var has_card := index < _cards.size()
		var button := Button.new()
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = CARD_MIN_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not has_card
		if has_card:
			var face := UiCardFace.body(_cards[index])
			if face != null:
				button.add_child(face)
				UiCardFace.fill_parent(face)
			var desc := str(_cards[index].get("desc", ""))
			if not desc.is_empty():
				button.tooltip_text = desc # 悬停 = 费用 + 效果描述
			button.pressed.connect(_on_card_pressed.bind(index))
			button.gui_input.connect(_on_card_gui_input.bind(index))
		else:
			var placeholder := Label.new()
			placeholder.text = EMPTY_TEXT
			placeholder.add_theme_font_size_override("font_size", 13)
			placeholder.add_theme_color_override("font_color", UiStyle.COLOR_TEXT_DIM)
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			button.add_child(placeholder)
			UiCardFace.fill_parent(placeholder, Vector4(0, 0, 0, 0))
		add_child(button)
	_apply_styles()


func _apply_styles() -> void:
	var index := 0
	for child in get_children():
		var button := child as Button
		if button != null:
			_style_button(button, button.disabled or index != _selected, index == _selected)
		index += 1


func _style_button(button: Button, is_plain: bool, is_selected: bool) -> void:
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	if is_plain and not is_selected and button.disabled:
		normal = UiStyle.empty_slot()
		hover = normal
		pressed = normal
	elif is_selected:
		normal = UiStyle.card(true)
		hover = UiStyle.card(true)
		pressed = UiStyle.card(true)
	else:
		normal = UiStyle.card(false)
		hover = UiStyle.card_hover()
		pressed = UiStyle.card(true)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("disabled", UiStyle.empty_slot() if button.disabled else UiStyle.card(false))
