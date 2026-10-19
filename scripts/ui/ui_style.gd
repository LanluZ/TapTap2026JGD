extends RefCounted
## UI 层共享样式：颜色常量 + StyleBoxFlat 构造。
## 仅供 scripts/ui/ 内部使用，不依赖任何逻辑层类型。
## 用法：const UiStyle = preload("res://scripts/ui/ui_style.gd")

## 色板：Pink Orchid #cdb4db / Pastel Petal #ffc8dd / Blush Pop #ffafcc / Icy Blue #bde0fe / Sky Blue #a2d2ff
## 底/面板为同色相压暗阶（保证文字对比度 ≥5:1），饱和粉蓝只做强调与高亮。
const COLOR_PANEL := Color(0.322, 0.224, 0.376, 1.0) # #523960
const COLOR_PANEL_DARK := Color(0.263, 0.180, 0.310, 1.0) # #432e4f
const COLOR_BORDER := Color(0.580, 0.482, 0.639, 1.0) # #947ba3
const COLOR_BORDER_SOFT := Color(0.463, 0.361, 0.518, 1.0) # #765c84
const COLOR_CARD := Color(0.384, 0.275, 0.447, 1.0) # #624672
const COLOR_CARD_HOVER := Color(0.427, 0.310, 0.490, 1.0) # #6d4f7d
const COLOR_CARD_SELECTED := Color(0.447, 0.231, 0.310, 1.0) # #723b4f
const COLOR_ACCENT := Color(1.000, 0.686, 0.800, 1.0) # #ffafcc Blush Pop
const COLOR_TEXT_DIM := Color(0.847, 0.820, 0.863, 1.0) # #d8d1dc
const COLOR_BAR_BG := Color(0.184, 0.122, 0.216, 1.0) # #2f1f37


static func flat(bg: Color, border: Color, margin: float, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_content_margin_all(margin)
	return box


static func panel() -> StyleBoxFlat:
	return flat(COLOR_PANEL, COLOR_BORDER, 8.0, 1)


static func card(selected: bool = false) -> StyleBoxFlat:
	if selected:
		return flat(COLOR_CARD_SELECTED, COLOR_ACCENT, 6.0, 2)
	return flat(COLOR_CARD, COLOR_BORDER, 6.0, 1)


static func card_hover() -> StyleBoxFlat:
	return flat(COLOR_CARD_HOVER, COLOR_ACCENT, 6.0, 1)


static func empty_slot() -> StyleBoxFlat:
	return flat(COLOR_PANEL_DARK, COLOR_BORDER_SOFT, 6.0, 1)


static func resource_slot() -> StyleBoxFlat:
	return flat(COLOR_PANEL_DARK, COLOR_BORDER_SOFT, 4.0, 1)


static func bar_background() -> StyleBoxFlat:
	return flat(COLOR_BAR_BG, COLOR_BORDER_SOFT, 0.0, 1)


static func bar_fill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box
