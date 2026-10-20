extends Control
## 场景：scenes/ui/menu_settings.tscn 主菜单设置界面（全屏遮罩 + 居中面板）。
##
## 两条音量滑块：背景音乐 / 音效。滑块 0..100 → 线性 0..1，写进 autoload Bgm / Sfx。
## 只作用于本次运行，不落盘（用户明确不要持久化）。
## 单例按树路径取，不写全局名——headless `-s` 与单场景 F6 下都不会报未定义标识符。

signal closed

const SfxScript = preload("res://scripts/ui/sfx.gd")
const DEFAULT_VOLUME := 0.8

@onready var _dim: ColorRect = $Dim
@onready var _bgm_slider: HSlider = $Center/Frame/VBox/BGMRow/Box/Slider
@onready var _bgm_value: Label = $Center/Frame/VBox/BGMRow/Box/Value
@onready var _sfx_slider: HSlider = $Center/Frame/VBox/SfxRow/Box/Slider
@onready var _sfx_value: Label = $Center/Frame/VBox/SfxRow/Box/Value
@onready var _close_btn: Button = $Center/Frame/VBox/Buttons/CloseButton

var _bgm := DEFAULT_VOLUME
var _sfx := DEFAULT_VOLUME


func _ready() -> void:
	_dim.gui_input.connect(_on_dim_input)
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_close_btn.pressed.connect(close)
	_sync_sliders()
	# 单独运行本场景（F6）时直接展示，方便调样式；作为子节点挂载时默认隐藏。
	if get_tree() != null and get_tree().current_scene == self:
		open()
	else:
		hide()


## 打开面板：滑块位置同步到当前音量并抓焦点。
func open() -> void:
	_sync_sliders()
	show()
	SfxScript.play_if_exists("展开")
	_close_btn.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	SfxScript.play_if_exists("收起")
	closed.emit()


func is_open() -> bool:
	return visible


## ESC = 关闭（菜单不暂停场景树，这里自己兜住）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## 点遮罩空白处关闭。
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _on_bgm_changed(v: float) -> void:
	_bgm = v / 100.0
	_bgm_value.text = "%d%%" % int(v)
	_apply()


func _on_sfx_changed(v: float) -> void:
	_sfx = v / 100.0
	_sfx_value.text = "%d%%" % int(v)
	_apply()


func _sync_sliders() -> void:
	_bgm_slider.set_value_no_signal(_bgm * 100.0)
	_sfx_slider.set_value_no_signal(_sfx * 100.0)
	_bgm_value.text = "%d%%" % int(_bgm * 100.0)
	_sfx_value.text = "%d%%" % int(_sfx * 100.0)


func _apply() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var bgm := tree.root.get_node_or_null("Bgm")
	if bgm != null:
		bgm.set_volume(_bgm)
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.set_volume(_sfx)
