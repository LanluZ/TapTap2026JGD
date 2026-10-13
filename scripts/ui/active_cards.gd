extends PanelContainer
## 生效中卡牌面板：固定槽位数量，空槽显示占位。数据由调用方注入。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiCardFace = preload("res://scripts/ui/card_face.gd")

const DEFAULT_SLOT_COUNT := 3
const MIN_SLOT_COUNT := 1
const MAX_SLOT_COUNT := 8
const EMPTY_TEXT := "空"

var _cards: Array = []
var _slot_count := DEFAULT_SLOT_COUNT
var _slots_box: HBoxContainer
var _count_label: Label
var _resolve_attempted := false


func _ready() -> void:
	_resolve()
	_rebuild()


func _resolve() -> void:
	if _resolve_attempted:
		return
	_resolve_attempted = true
	_slots_box = get_node_or_null("VBox/Slots") as HBoxContainer
	_count_label = get_node_or_null("VBox/Head/Count") as Label
	if _slots_box == null:
		push_error("[生效中卡牌] 缺少 VBox/Slots 节点，检查 main.tscn")


## 生效中的卡牌列表（元素为卡牌 Dictionary，非法项跳过并警告）
func set_cards(cards: Array) -> void:
	_resolve()
	_cards.clear()
	for card in cards:
		if card is Dictionary:
			_cards.append(card)
		else:
			push_warning("[生效中卡牌] 跳过非法卡牌项：%s" % str(card))
	_rebuild()


func get_cards() -> Array:
	return _cards.duplicate()


func set_slot_count(count: int) -> void:
	_slot_count = clampi(count, MIN_SLOT_COUNT, MAX_SLOT_COUNT)
	_resolve()
	_rebuild()


func get_slot_count() -> int:
	return _slot_count


func _rebuild() -> void:
	if _slots_box == null:
		return
	for child in _slots_box.get_children():
		_slots_box.remove_child(child)
		child.free()
	var total := maxi(_slot_count, _cards.size())
	for index in total:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(76, 100)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if index < _cards.size():
			slot.add_theme_stylebox_override("panel", UiStyle.card(false))
			var face := UiCardFace.body(_cards[index])
			if face != null:
				slot.add_child(face)
		else:
			slot.add_theme_stylebox_override("panel", UiStyle.empty_slot())
			var placeholder := Label.new()
			placeholder.text = EMPTY_TEXT
			placeholder.add_theme_font_size_override("font_size", 13)
			placeholder.add_theme_color_override("font_color", UiStyle.COLOR_TEXT_DIM)
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
			slot.add_child(placeholder)
		_slots_box.add_child(slot)
	if _count_label != null:
		_count_label.text = "%d / %d" % [_cards.size(), _slot_count]
