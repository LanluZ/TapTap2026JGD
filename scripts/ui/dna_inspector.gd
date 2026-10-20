extends Control
## DNA 检视预制体（策划案 15.8 玩家视图，河阳式布局）：
## 左列碱基字母纵列（每座一对字母，杂合两个字母各用自己的颜色；不展开座名）→ 中央双螺旋插画 + 座数徽章
## → 右侧卡面形象（art 路径，空则整区隐藏）→ 底部融合规则 + 调试行。
## 场景预制体 scenes/ui/dna_inspector.tscn 的根脚本，可嵌套进任意容器。
## 纯数据注入（set_view），不引用逻辑层任何类型：
##   {title, bases, locus_names, rules, debug, art?}（art = 卡面贴图 res:// 路径，可选）
## bases 每项 = 该座一对碱基（"AT" 杂合 / "AA" 纯合 / "—" 空座 / "·" 地块占位）；
## 旧单字母载荷（"A"）照旧只显示一个字母，不在表现层补成双写。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const BASE_COLORS := {
	"A": Color(0.451, 0.851, 0.522), # #73d985
	"T": Color(0.949, 0.549, 0.451), # #f28c73
	"C": Color(0.502, 0.702, 0.949), # #80b3f2
	"G": Color(0.949, 0.851, 0.451), # #f2d973
}
const COLOR_EMPTY := Color(0.42, 0.40, 0.47)
## 空座占位（"—"）与地块卡占位（"·"）都不是碱基字母：_letters_in 返回 0 个 → 整行灰色、不计入座数。
const EMPTY_BASES := ["—", "·"]


## 双螺旋插画：两条相位差 π 的正弦链 + 每座一根碱基色横档。
## 横档按二倍体拆成左右两半：杂合时左半用第一个字母的颜色、右半用第二个字母的颜色。
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

	## 该座的一对字母（"AT"/"AA" → 2 个；旧单字母 → 1 个；"—"/"·" → 0 个）。
	## 与外层 _letters_in 同逻辑：内层类取不到外层常量，故各留一份。
	static func letters_in(entry: String) -> Array:
		var out: Array = []
		for i in entry.length():
			var ch := entry.substr(i, 1)
			if HELIX_COLORS.has(ch):
				out.append(ch)
		return out

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
		# 横档：每座一条，杂合时左右两半各用各的字母色
		var n := bases.size()
		for i in n:
			var y := (float(i) + 0.5) * h / float(n)
			var ang := (y / h) * TAU * twists
			var x1 := cx + sin(ang) * amp
			var x2 := cx + sin(ang + PI) * amp
			var ls := letters_in(str(bases[i]))
			var left := minf(x1, x2)
			var width := absf(x1 - x2)
			if ls.size() < 2:
				var c: Color = HELIX_EMPTY
				if ls.size() == 1:
					c = HELIX_COLORS.get(str(ls[0]), HELIX_EMPTY)
				draw_rect(Rect2(left, y - 2.0, width, 4.0), c)
			else:
				var mid := left + width * 0.5
				draw_rect(Rect2(left, y - 2.0, width * 0.5, 4.0), HELIX_COLORS.get(str(ls[0]), HELIX_EMPTY))
				draw_rect(Rect2(mid, y - 2.0, width * 0.5, 4.0), HELIX_COLORS.get(str(ls[1]), HELIX_EMPTY))


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
	_build_parts()


## 程序化补建（双螺旋 / 卡面贴图），幂等：set_view 可能先于 _ready 到达
## （弹窗在 main_ui 里是 add_child.call_deferred 挂树的）。
func _build_parts() -> void:
	if not _resolved or _helix != null:
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
	_build_parts()
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


## 座数按「有基因的座位数 / 总座位数」计（不按字母数）：杂合座两个字母仍算 1 座。
func _occupied_count(bases: Array) -> int:
	var n := 0
	for b in bases:
		if not _letters_in(str(b)).is_empty():
			n += 1
	return n


## 该座的一对字母（"AT"/"AA" → 2 个；旧单字母 → 1 个；"—"/"·"/空 → 0 个）。
static func _letters_in(entry: String) -> Array:
	var out: Array = []
	if entry in EMPTY_BASES:
		return out
	for i in entry.length():
		var ch := entry.substr(i, 1)
		if BASE_COLORS.has(ch):
			out.append(ch)
	return out


## 一对字母 → BBCode（逐字母上色）：杂合时两个字母各用自己的碱基色。
static func _colored_letters(letters: Array) -> String:
	var parts: Array = []
	for l in letters:
		var c: Color = BASE_COLORS.get(str(l), COLOR_EMPTY)
		parts.append("[color=#%s]%s[/color]" % [c.to_html(false), str(l)])
	return "".join(parts)


## 左列：碱基字母纵列（每座一行，一行 1~2 个字母；座名进 tooltip，不占版面）
## 用 RichTextLabel 才能一行里给两个字母上不同的碱基色；单字母/空座仍是纯文本，text 可直接读。
func _fill_bases(bases: Array, locus_names: Array) -> void:
	for child in _base_list.get_children():
		_base_list.remove_child(child)
		child.free()
	_left_col.visible = not bases.is_empty()
	for i in bases.size():
		var raw := str(bases[i])
		var letters := _letters_in(raw)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		label.add_theme_font_size_override("normal_font_size", 20)
		if letters.size() >= 2:
			label.text = _colored_letters(letters)
			label.add_theme_color_override("default_color", BASE_COLORS.get(str(letters[0]), COLOR_EMPTY))
		else:
			# 单字母（旧载荷）/ 空座占位：纯文本，颜色整行一种
			label.text = raw if not raw.is_empty() else "—"
			label.add_theme_color_override("default_color",
				BASE_COLORS.get(str(letters[0]), COLOR_EMPTY) if not letters.is_empty() else COLOR_EMPTY)
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
