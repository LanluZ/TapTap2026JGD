extends Control
## DNA 检视预制体（策划案 15.8 玩家视图）：碱基互补配对链 + 融合规则 + 调试开关。
## 场景预制体 scenes/ui/dna_inspector.tscn 的根脚本，可嵌套进任意容器。
## 纯数据注入（set_view），不引用逻辑层任何类型；
## 骨架与配色在 .tscn（风格对齐 ui_style.gd / main.tscn），脚本只填数据与动态碱基格。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const BASE_COLORS := {
	"A": Color(0.45, 0.85, 0.5),
	"T": Color(0.95, 0.55, 0.45),
	"C": Color(0.5, 0.7, 0.95),
	"G": Color(0.95, 0.85, 0.45),
}
const COLOR_EMPTY := Color(0.55, 0.55, 0.6)
const EMPTY_BASES := ["—"] # 空座（该座无基因）；"·" 是地块卡占位，算有座

var _title: Label
var _count: Label
var _chain_section: PanelContainer
var _chain: HBoxContainer
var _rules_section: PanelContainer
var _rules: VBoxContainer
var _debug_toggle: CheckButton
var _debug_panel: PanelContainer
var _debug_text: Label
var _resolved := false


func _ready() -> void:
	_resolve()
	if not _resolved:
		return
	_debug_toggle.toggled.connect(_on_debug_toggled)


func _resolve() -> void:
	if _resolved:
		return
	_title = get_node_or_null("Box/Header/TitleBlock/Title") as Label
	_count = get_node_or_null("Box/Header/LociBadge/Count") as Label
	_chain_section = get_node_or_null("Box/ChainSection") as PanelContainer
	_chain = get_node_or_null("Box/ChainSection/ChainBox/Scroll/Chain") as HBoxContainer
	_rules_section = get_node_or_null("Box/RulesSection") as PanelContainer
	_rules = get_node_or_null("Box/RulesSection/RulesBox/Rules") as VBoxContainer
	_debug_toggle = get_node_or_null("Box/DebugRow/DebugToggle") as CheckButton
	_debug_panel = get_node_or_null("Box/DebugPanel") as PanelContainer
	_debug_text = get_node_or_null("Box/DebugPanel/DebugText") as Label
	_resolved = _title != null and _count != null and _chain != null \
		and _rules != null and _debug_toggle != null and _debug_text != null
	if not _resolved:
		push_error("[DNA检视] 场景节点与脚本不匹配，检查 scenes/ui/dna_inspector.tscn")


## data: {title: String, bases: Array（每座碱基或占位符）, locus_names: Array,
##        rules: Array[String], debug: String}
func set_view(data: Dictionary) -> void:
	_resolve()
	if not _resolved:
		return
	_title.text = str(data.get("title", "DNA 检视"))
	var bases: Array = data.get("bases", [])
	_fill_chain(bases, data.get("locus_names", []))
	_count.text = "%d / %d 座" % [_occupied_count(bases), bases.size()]
	_fill_rules(data.get("rules", []))
	var debug := str(data.get("debug", ""))
	_debug_text.text = debug
	_debug_toggle.visible = not debug.is_empty() # 没有原始序列就不占一行
	_debug_toggle.button_pressed = false         # 每次打开都收起
	_debug_panel.visible = false


func _occupied_count(bases: Array) -> int:
	var n := 0
	for b in bases:
		if not str(b) in EMPTY_BASES:
			n += 1
	return n


func _fill_chain(bases: Array, locus_names: Array) -> void:
	for child in _chain.get_children():
		_chain.remove_child(child)
		child.free()
	_chain_section.visible = not bases.is_empty()
	for i in bases.size():
		var name := str(locus_names[i]) if i < locus_names.size() else ""
		_chain.add_child(_cell(str(bases[i]), name))


## 一个基因座 = 碱基胶囊 / 横档 / 互补胶囊 / 座名（碱基互补配对链 策划案 15.8）
func _cell(base: String, locus_name: String) -> VBoxContainer:
	var occupied := not (base in EMPTY_BASES)
	var color: Color = BASE_COLORS.get(base, COLOR_EMPTY)
	var bottom := _complement_of(base)
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 0)
	cell.add_child(_chip(base, color, occupied))
	cell.add_child(_rung(color, occupied))
	cell.add_child(_chip(bottom, BASE_COLORS.get(bottom, COLOR_EMPTY), occupied))

	var name_label := Label.new()
	name_label.text = locus_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", color if occupied else COLOR_EMPTY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(46, 0)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var name_box := MarginContainer.new()
	name_box.add_theme_constant_override("margin_top", 4)
	name_box.add_child(name_label)
	cell.add_child(name_box)
	return cell


func _chip(letter: String, color: Color, occupied: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.14 if occupied else 0.05)
	box.border_color = Color(color.r, color.g, color.b, 0.55 if occupied else 0.25)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(4.0)
	box.content_margin_left = 9.0
	box.content_margin_right = 9.0
	chip.add_theme_stylebox_override("panel", box)

	var label := Label.new()
	label.text = letter
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", color if occupied else COLOR_EMPTY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(label)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return chip


func _rung(color: Color, occupied: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(16 if occupied else 8, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.color = Color(color.r, color.g, color.b, 0.85 if occupied else 0.3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _fill_rules(rules: Array) -> void:
	for child in _rules.get_children():
		_rules.remove_child(child)
		child.free()
	_rules_section.visible = not rules.is_empty()
	for r in rules:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var bullet := Label.new()
		bullet.text = "•"
		bullet.add_theme_font_size_override("font_size", 12)
		bullet.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
		row.add_child(bullet)

		var line := Label.new()
		line.text = str(r)
		line.add_theme_font_size_override("font_size", 12)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		_rules.add_child(row)


func _complement_of(base: String) -> String:
	match base:
		"A": return "T"
		"T": return "A"
		"C": return "G"
		"G": return "C"
		_: return base


func _on_debug_toggled(on: bool) -> void:
	_debug_panel.visible = on and not _debug_text.text.is_empty()
