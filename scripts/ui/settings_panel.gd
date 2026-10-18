extends Control
## 场景：scenes/ui/settings_panel.tscn 设置面板（全屏遮罩 + 居中面板）。
##
## 独立场景，由关卡 main.tscn 实例化为 SettingsPanel 节点；main_ui.gd 在
## ESC 时调用 open()。打开时暂停整棵场景树（本节点 process_mode = WHEN_PAUSED，
## 所以暂停后仍能收输入），「返回游戏」恢复运行。
## 「返回标题」只发信号，场景切换由上层决定——本脚本不含任何场景路径。
## 设置项后续加进 Content 容器（get_content()），不用改本脚本。

signal resume_requested()
signal title_requested()

## 打开时是否暂停整棵场景树。挂到不需要暂停的场景（如主菜单）时置 false。
@export var pause_tree_on_open: bool = true

@onready var _content: VBoxContainer = $Center/Panel/VBox/Content
@onready var _resume_btn: Button = $Center/Panel/VBox/Buttons/ResumeButton
@onready var _title_btn: Button = $Center/Panel/VBox/Buttons/TitleButton

var _paused_by_me := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_resume_btn.pressed.connect(_on_resume_pressed)
	_title_btn.pressed.connect(_on_title_pressed)
	# 单独运行本场景（F6）时直接展示，方便调样式；作为子节点挂载时默认隐藏。
	if get_tree() != null and get_tree().current_scene == self:
		show()
	else:
		hide()


## 设置项容器（后续设置控件加到这里）。
func get_content() -> VBoxContainer:
	return _content


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	show()
	if pause_tree_on_open and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_resume_btn.grab_focus()


func close() -> void:
	if visible:
		hide()
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false


## 面板打开时 ESC = 返回游戏（暂停态下 main_ui 收不到输入，这里兜住）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_resume_pressed()
		get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	close()
	resume_requested.emit()


## 切场景前必须先解除暂停，否则新场景开局即 frozen。
func _on_title_pressed() -> void:
	close()
	title_requested.emit()
