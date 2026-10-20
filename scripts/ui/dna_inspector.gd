extends Control
## DNA 检视预制体（策划案 15.8 玩家视图，河阳式布局）：
## 左列碱基字母纵列（只显示 A/T/C/G，不展开座名）→ 中央双螺旋插画 + 座数徽章
## → 右侧卡面形象（art 路径，空则整区隐藏）→ 底部融合规则 + 调试行。
## 场景预制体 scenes/ui/dna_inspector.tscn 的根脚本，可嵌套进任意容器。
## 纯数据注入（set_view），不引用逻辑层任何类型：
##   {title, bases, locus_names, rules, debug, art?}（art = 卡面贴图 res:// 路径，可选）

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const BASE_COLORS := {
	"A": Color(0.451, 0.851, 0.522), # #73d985
	"T": Color(0.949, 0.549, 0.451), # #f28c73
	"C": Color(0.502, 0.702, 0.949), # #80b3f2
	"G": Color(0.949, 0.851, 0.451), # #f2d973
}
const COLOR_EMPTY := Color(0.42, 0.40, 0.47)
const EMPTY_BASES := ["—", "·"] # 空座（该座无基因）；"·" 是地块卡占位，算有座


## 双螺旋插画：两条相位差 π 的正弦链 + 每座一根碱基色横档。
## 颜色表在此类内重复一份：内层类不捕获外层常量， headless 下直接引用会解析失败。
class HelixView extends Control:
	const HELIX_COLORS := {
		"A": Color(0.451, 0.851, 0.522),
		"T": Color(0.949, 0.549, 0.451),
		"C": Color(0.502, 0.702, 0.949),
		"G": Color(0.949, 0.851, 0.451),
	}
	const HELIX_EMPTY := Color(0.42, 0.40, 0.47)

	var bases: Array = []

	func set_bases(b: Array) -> void:
		bases = b
		queue_redraw()

	func _draw() -> void:
		if size.y <= 1.0:
			return
		var cx := size.x * 0.5
		var amp := size.x * 0.30
		var h := size.y
		var twists := 2.2 # 全高扭转圈数
		var p1 := PackedVector2Array()
		var p2 := PackedVector2Array()
		var steps := maxi(int(h / 3.0), 8)
		for i in steps + 1:
			var y := h * float(i) / float(steps)
			var ang := (y / h) * TAU * twists
			p1.append(Vector2(cx + sin(ang) * amp, y))
			p2.append(Vector2(cx + sin(ang + PI) * amp, y))
		draw_polyline(p1, Color(0.81, 0.81, 0.84), 5.0)
		draw_polyline(p2, Color(0.56, 0.56, 0.60), 5.0)
		if bases.is_empty():
			return
		# 横档：每座一条，颜色 = 该座碱基色（互补对同色）
		var n := bases.size()
		for i in n:
			var y := (float(i) + 0.5) * h / float(n)
			var ang := (y / h) * TAU * twists
			var x1 := cx + sin(ang) * amp
			var x2 := cx + sin(ang + PI) * amp
			var letter := str(bases[i])
			var c: Color = HELIX_COLORS.get(letter, HELIX_EMPTY) \
				if not (letter in ["—", "·"]) else HELIX_EMPTY
			draw_rect(Rect2(minf(x1, x2), y - 2.0, absf(x1 - x2), 4.0), c)


var _title: Label
var _base_list: VBoxContainer
var _left_col: VBoxContainer
var _helix_host: Control
var _helix: HelixView
var _badge_count: Label
var _badge: PanelContainer
var _figure_panel: PanelContainer
var _figure_host: Control
var _rules_section: PanelContainer
var _rules: VBoxContainer
var _debug_toggle: CheckButton
var _debug_panel: PanelContainer
var _debug_text: Label
var _figure_tex: TextureRect
var _resolved := false


func _ready() -> void:
	_resolve()
	if not _resolved:
		return
	_debug_toggle.toggled.connect(_on_debug_toggled)
	# 双螺旋插画在骨架里只有一个空 Host，程序化补建（不动 .tscn）
	_helix = HelixView.new()
	_helix.name = "HelixView"
	_helix.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_helix_host.add_child(_helix)
	_helix.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_figure_tex = TextureRect.new()
	_figure_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_figure_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_figure_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_figure_host.add_child(_figure_tex)
	_figure_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _resolve() -> void:
	if _resolved:
		return
	_title = get_node_or_null("Box/Header/TitleBlock/Title") as Label
	_left_col = get_node_or_null("Box/Main/LeftCol") as VBoxContainer
	_base_list = get_node_or_null("Box/Main/LeftCol/BaseList") as VBoxContainer
	_helix_host = get_node_or_null("Box/Main/HelixCol/HelixHost") as Control
	_badge = get_node_or_null("Box/Main/HelixCol/Badge") as PanelContainer
	_badge_count = get_node_or_null("Box/Main/HelixCol/Badge/Count") as Label
	_figure_panel = get_node_or_null("Box/Main/FigurePanel") as PanelContainer
	_figure_host = get_node_or_null("Box/Main/FigurePanel/FigureHost") as Control
	_rules_section = get_node_or_null("Box/RulesSection") as PanelContainer
	_rules = get_node_or_null("Box/RulesSection/RulesBox/Rules") as VBoxContainer
	_debug_toggle = get_node_or_null("Box/DebugRow/DebugToggle") as CheckButton
	_debug_panel = get_node_or_null("Box/DebugPanel") as PanelContainer
	_debug_text = get_node_or_null("Box/DebugPanel/DebugText") as Label
	_resolved = _title != null and _base_list != null and _helix_host != null \
		and _badge_count != null and _figure_host != null and _rules != null \
		and _debug_toggle != null and _debug_text != null
	if not _resolved:
		push_error("[DNA检视] 场景节点与脚本不匹配，检查 scenes/ui/dna_inspector.tscn")


## data: {title: String, bases: Array（每座碱基或占位符）, locus_names: Array,
##        rules: Array[String], debug: String, art: String（可选卡面贴图路径）}
func set_view(data: Dictionary) -> void:
	_resolve()
	if not _resolved:
		return
	_title.text = str(data.get("title", "DNA 检视"))
	var bases: Array = data.get("bases", [])
	_fill_bases(bases, data.get("locus_names", []))
	var occupied := _occupied_count(bases)
	_badge.visible = not bases.is_empty()
	_badge_count.text = "%d / %d 座" % [occupied, bases.size()]
	_helix.set_bases(bases)
	_set_figure(str(data.get("art", "")))
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


## 左列：碱基字母纵列（只写字母；座名进 tooltip，不占版面）
func _fill_bases(bases: Array, locus_names: Array) -> void:
	for child in _base_list.get_children():
		_base_list.remove_child(child)
		child.free()
	_left_col.visible = not bases.is_empty()
	for i in bases.size():
		var letter := str(bases[i])
		var occupied := not (letter in EMPTY_BASES)
		var label := Label.new()
		label.text = letter
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color",
			BASE_COLORS.get(letter, COLOR_EMPTY) if occupied else COLOR_EMPTY)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i < locus_names.size():
			label.tooltip_text = str(locus_names[i])
		_base_list.add_child(label)


## 右侧形象区：art 路径加载成功才显示；空/失败整区收起（不伪造外观）
func _set_figure(art_path: String) -> void:
	var tex: Texture2D = load(art_path) if not art_path.is_empty() else null
	_figure_tex.texture = tex
	_figure_panel.visible = tex != null


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


func _on_debug_toggled(on: bool) -> void:
	_debug_panel.visible = on and not _debug_text.text.is_empty()
