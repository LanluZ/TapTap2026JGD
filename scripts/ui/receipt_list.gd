extends PanelContainer
## 战报 / 回执列表：追加式消息列表，内容由调用方注入。
## 元素支持 String（直接显示）或 Dictionary{ icon: String, text: String }，非法项跳过并警告。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const MAX_ITEMS := 50
const DEFAULT_ICON := "!"

var _items: Array = []
var _list: VBoxContainer
var _resolve_attempted := false


func _ready() -> void:
	_resolve()
	_rebuild()


func _resolve() -> void:
	if _resolve_attempted:
		return
	_resolve_attempted = true
	_list = get_node_or_null("VBox/Body/List") as VBoxContainer
	if _list == null:
		push_error("[战报] 缺少 VBox/Body/List 节点，检查 main.tscn")


func set_items(items: Array) -> void:
	_resolve()
	_items.clear()
	for item in items:
		if item is String or (item is Dictionary and item.has("text")):
			_items.append(item)
		else:
			push_warning("[战报] 跳过非法消息项：%s" % str(item))
	if _items.size() > MAX_ITEMS:
		push_warning("[战报] 消息超过 %d 条，仅显示最后 %d 条" % [MAX_ITEMS, MAX_ITEMS])
		_items = _items.slice(_items.size() - MAX_ITEMS)
	_rebuild()


func get_items() -> Array:
	return _items.duplicate()


func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.free()
	for item in _items:
		var icon_text := DEFAULT_ICON
		var text := ""
		if item is String:
			text = item
		else:
			icon_text = str(item.get("icon", DEFAULT_ICON))
			text = str(item.get("text", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var icon := Label.new()
		icon.text = icon_text
		icon.add_theme_font_size_override("font_size", 12)
		icon.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
		icon.custom_minimum_size = Vector2(20, 0)

		var body := Label.new()
		body.text = text
		body.add_theme_font_size_override("font_size", 12)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		row.add_child(icon)
		row.add_child(body)
		_list.add_child(row)
