extends RefCounted
## 卡牌 Dictionary 的规范化 + 卡面节点构造（scripts/ui/ 共用）。
## 卡牌是纯数据 Dictionary，UI 不引用任何逻辑层类型：
##   id   : String  配置 id（可选）
##   name : String  卡面名
##   kind : String  "factory" | "tile"（其他值原样显示为标签）
##   icon : String  卡面文字图形（可选，非空才显示；art 优先于 icon）
##   art  : String  卡面贴图 res:// 路径（可选，非空且加载成功 → TextureRect，不再显示 icon/名称行）
##   desc : String  描述（可选，当前仅作 tooltip）
##   cost : String  消耗文案（可选，卡费+蓝图费合计，如 "零件×10"；空则不显示消耗行）

const FIELDS: Array[String] = ["id", "name", "kind", "icon", "art", "desc", "cost"]
const KIND_LABELS := {"factory": "工厂", "tile": "地块"}
const FALLBACK_NAME := "???"

const UiStyle = preload("res://scripts/ui/ui_style.gd")


## 规范化一张卡牌；非 Dictionary 返回空字典（调用方据此跳过）。
static func normalize(card) -> Dictionary:
	var out := {}
	if not (card is Dictionary):
		return out
	for field in FIELDS:
		var value = card.get(field, "")
		out[field] = "" if value == null else str(value)
	if out["name"].is_empty():
		out["name"] = out["id"] if not out["id"].is_empty() else FALLBACK_NAME
	return out


static func kind_label(kind: String) -> String:
	if kind.is_empty():
		return "卡牌"
	return str(KIND_LABELS.get(kind, kind))


## 构造卡面（VBox：贴图版=图+消耗 / 文字版=标签/图形/名称/消耗）。返回 null 表示数据非法。
## 放进 Button（手牌）时由调用方设为 FULL_RECT；放进 PanelContainer 时由容器排版。
static func body(card) -> VBoxContainer:
	var data := normalize(card)
	if data.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	# 贴图卡面：整图自带名称/框体，只在下方补消耗行（运行时费用，图里没有）
	if not data["art"].is_empty():
		var tex: Texture2D = load(data["art"])
		if tex != null:
			var art := TextureRect.new()
			art.texture = tex
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.size_flags_vertical = Control.SIZE_EXPAND_FILL
			box.add_child(art)
			if not data["cost"].is_empty():
				box.add_child(_cost_label(data["cost"]))
			box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			return box
		push_warning("[卡面] 贴图加载失败，回退文字卡面: " + data["art"])

	var tag := Label.new()
	tag.text = kind_label(data["kind"])
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not data["icon"].is_empty():
		var icon := Label.new()
		icon.text = data["icon"]
		icon.add_theme_font_size_override("font_size", 30)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(icon)

	var title := Label.new()
	title.text = data["name"]
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	box.add_child(tag)
	box.add_child(title)
	if not data["cost"].is_empty():
		box.add_child(_cost_label(data["cost"]))
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return box


## 消耗行标签（贴图版/文字版卡面共用）。
static func _cost_label(cost_text: String) -> Label:
	var cost := Label.new()
	cost.text = "消耗: " + cost_text
	cost.add_theme_font_size_override("font_size", 11)
	cost.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.clip_text = true
	cost.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return cost


## 把卡面铺满父节点并留出内边距（父节点须为非容器 Control，如 Button）。
static func fill_parent(face: Control, pad := Vector4(6.0, 4.0, 6.0, 4.0)) -> void:
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.offset_left = pad.x
	face.offset_top = pad.y
	face.offset_right = -pad.z
	face.offset_bottom = -pad.w
