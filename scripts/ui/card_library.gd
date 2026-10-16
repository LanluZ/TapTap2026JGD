extends PanelContainer
## 卡牌库面板：只读列表 + 展开/收起。数据由调用方注入（关卡卡池等由逻辑层决定）。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiCardFace = preload("res://scripts/ui/card_face.gd")

var _cards: Array = []
var _expanded := true
var _list: VBoxContainer
var _body: Control
var _toggle: Button
var _count_label: Label
var _resolve_attempted := false


func _ready() -> void:
	_resolve()
	_apply_expanded()
	_rebuild()


func _resolve() -> void:
	if _resolve_attempted:
		return
	_resolve_attempted = true
	_list = get_node_or_null("VBox/Body/List") as VBoxContainer
	_body = get_node_or_null("VBox/Body") as Control
	_toggle = get_node_or_null("VBox/Head/Toggle") as Button
	_count_label = get_node_or_null("VBox/Head/Count") as Label
	if _list == null or _body == null or _toggle == null:
		push_error("[卡牌库] 缺少 VBox/Head 或 VBox/Body 节点，检查 main.tscn")
		return
	_toggle.pressed.connect(toggle_expanded)


## 卡牌库内容（元素为卡牌 Dictionary，非法项跳过并警告）
func set_cards(cards: Array) -> void:
	_resolve()
	_cards.clear()
	for card in cards:
		if card is Dictionary:
			_cards.append(card)
		else:
			push_warning("[卡牌库] 跳过非法卡牌项：%s" % str(card))
	_rebuild()


func get_cards() -> Array:
	return _cards.duplicate()


func set_expanded(expanded: bool) -> void:
	_resolve()
	_expanded = expanded
	_apply_expanded()


func toggle_expanded() -> void:
	set_expanded(not _expanded)


func is_expanded() -> bool:
	return _expanded


func _apply_expanded() -> void:
	if _body != null:
		_body.visible = _expanded
	if _toggle != null:
		_toggle.text = "收起" if _expanded else "展开"


func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.free()
	for card in _cards:
		var data := UiCardFace.normalize(card)
		if data.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		if not data["icon"].is_empty():
			var icon := Label.new()
			icon.text = data["icon"]
			icon.add_theme_font_size_override("font_size", 16)
			icon.custom_minimum_size = Vector2(22, 0)
			row.add_child(icon)

		var title := Label.new()
		title.text = data["name"]
		title.add_theme_font_size_override("font_size", 13)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

		var kind := Label.new()
		kind.text = UiCardFace.kind_label(data["kind"])
		kind.add_theme_font_size_override("font_size", 11)
		kind.add_theme_color_override("font_color", UiStyle.COLOR_TEXT_DIM)

		row.add_child(title)
		if not data["cost"].is_empty():
			var cost := Label.new()
			cost.text = "消耗: " + data["cost"]
			cost.add_theme_font_size_override("font_size", 11)
			cost.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
			row.add_child(cost)
		row.add_child(kind)
		_list.add_child(row)
	if _count_label != null:
		_count_label.text = "%d" % _cards.size()
