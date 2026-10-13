extends RefCounted
## UI 层共享样式：颜色常量 + StyleBoxFlat 构造。
## 仅供 scripts/ui/ 内部使用，不依赖任何逻辑层类型。
## 用法：const UiStyle = preload("res://scripts/ui/ui_style.gd")

const COLOR_PANEL := Color(0.17, 0.17, 0.19, 1.0)
const COLOR_PANEL_DARK := Color(0.12, 0.12, 0.14, 1.0)
const COLOR_BORDER := Color(0.4, 0.4, 0.46, 1.0)
const COLOR_BORDER_SOFT := Color(0.28, 0.28, 0.33, 1.0)
const COLOR_CARD := Color(0.24, 0.24, 0.27, 1.0)
const COLOR_CARD_HOVER := Color(0.3, 0.3, 0.35, 1.0)
const COLOR_CARD_SELECTED := Color(0.3, 0.25, 0.17, 1.0)
const COLOR_ACCENT := Color(0.88, 0.57, 0.24, 1.0)
const COLOR_TEXT_DIM := Color(0.62, 0.63, 0.68, 1.0)
const COLOR_BAR_BG := Color(0.09, 0.09, 0.1, 1.0)


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
