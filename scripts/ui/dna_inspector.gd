extends Control
## DNA 检视预制体（策划案 15.8 玩家视图）：碱基互补配对链 + 融合规则 + 调试开关。
## 场景预制体 scenes/ui/dna_inspector.tscn 的根脚本，可嵌套进任意容器。
## 纯数据注入（set_view），不引用逻辑层任何类型；内部布局程序化构建。

const BASE_COLORS := {
	"A": Color(0.45, 0.85, 0.5),
	"T": Color(0.95, 0.55, 0.45),
	"C": Color(0.5, 0.7, 0.95),
	"G": Color(0.95, 0.85, 0.45),
}
const COLOR_EMPTY := Color(0.55, 0.55, 0.6)

var _chain: HBoxContainer
var _rules: VBoxContainer
var _debug_label: Label
var _debug_toggle: CheckButton
var _title: Label
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	_title = Label.new()
	_title.text = "DNA 检视"
	_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_title)

	# 碱基互补配对链：上排 = 本卡碱基，下排 = 互补碱基（A↔T、C↔G）
	_chain = HBoxContainer.new()
	_chain.add_theme_constant_override("separation", 10)
	vbox.add_child(_chain)

	# 融合规则（数据注入，数字来自 genes.json）
	_rules = VBoxContainer.new()
	_rules.add_theme_constant_override("separation", 2)
	vbox.add_child(_rules)

	_debug_toggle = CheckButton.new()
	_debug_toggle.text = "调试：原始序列"
	_debug_toggle.toggled.connect(_on_debug_toggled)
	vbox.add_child(_debug_toggle)

	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.visible = false
	vbox.add_child(_debug_label)


## data: {title: String, bases: Array（每座碱基或"—"）, locus_names: Array,
##        rules: Array[String], debug: String}
func set_view(data: Dictionary) -> void:
	_prepare()
	_title.text = str(data.get("title", "DNA 检视"))
	_fill_chain(data.get("bases", []), data.get("locus_names", []))
	_fill_rules(data.get("rules", []))
	_debug_label.text = str(data.get("debug", ""))


func _prepare() -> void:
	if not _built:
		_build()


func _fill_chain(bases: Array, locus_names: Array) -> void:
	for child in _chain.get_children():
		_chain.remove_child(child)
		child.free()
	for i in bases.size():
		var base := str(bases[i])
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)

		var top := Label.new()
		top.text = base
		top.add_theme_font_size_override("font_size", 22)
		top.add_theme_color_override("font_color", BASE_COLORS.get(base, COLOR_EMPTY))
		top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(top)

		var link := Label.new()
		link.text = "│" if base != "—" else "·"
		link.add_theme_color_override("font_color", COLOR_EMPTY)
		link.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(link)

		var bottom := Label.new()
		bottom.text = _complement_of(base)
		bottom.add_theme_font_size_override("font_size", 22)
		bottom.add_theme_color_override("font_color", BASE_COLORS.get(bottom.text, COLOR_EMPTY))
		bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(bottom)

		var name_label := Label.new()
		name_label.text = str(locus_names[i]) if i < locus_names.size() else ""
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", COLOR_EMPTY)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_label)

		_chain.add_child(cell)


func _fill_rules(rules: Array) -> void:
	for child in _rules.get_children():
		_rules.remove_child(child)
		child.free()
	for r in rules:
		var line := Label.new()
		line.text = str(r)
		line.add_theme_font_size_override("font_size", 12)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rules.add_child(line)


func _complement_of(base: String) -> String:
	match base:
		"A": return "T"
		"T": return "A"
		"C": return "G"
		"G": return "C"
		_: return base


func _on_debug_toggled(on: bool) -> void:
	_debug_label.visible = on and not _debug_label.text.is_empty()
