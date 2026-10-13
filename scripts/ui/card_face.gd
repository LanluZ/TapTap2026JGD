extends RefCounted
## 卡牌 Dictionary 的规范化 + 卡面节点构造（scripts/ui/ 共用）。
## 卡牌是纯数据 Dictionary，UI 不引用任何逻辑层类型：
##   id   : String  配置 id（可选）
##   name : String  卡面名
##   kind : String  "factory" | "tile"（其他值原样显示为标签）
##   icon : String  卡面图形（可选，emoji/字符）
##   desc : String  描述（可选，当前仅作 tooltip）

const FIELDS: Array[String] = ["id", "name", "kind", "icon", "desc"]
const KIND_LABELS := {"factory": "工厂", "tile": "地块"}
const FALLBACK_NAME := "???"
const FALLBACK_ICON := "◇"

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


## 构造卡面（VBox：标签 / 图形 / 名称）。返回 null 表示数据非法。
## 放进 Button（手牌）时由调用方设为 FULL_RECT；放进 PanelContainer 时由容器排版。
static func body(card) -> VBoxContainer:
	var data := normalize(card)
	if data.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var tag := Label.new()
	tag.text = kind_label(data["kind"])
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", UiStyle.COLOR_ACCENT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var icon := Label.new()
	icon.text = data["icon"] if not data["icon"].is_empty() else FALLBACK_ICON
	icon.add_theme_font_size_override("font_size", 30)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = data["name"]
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	box.add_child(tag)
	box.add_child(icon)
	box.add_child(title)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return box


## 把卡面铺满父节点并留出内边距（父节点须为非容器 Control，如 Button）。
static func fill_parent(face: Control, pad := Vector4(6.0, 4.0, 6.0, 4.0)) -> void:
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.offset_left = pad.x
	face.offset_top = pad.y
	face.offset_right = -pad.z
	face.offset_bottom = -pad.w
