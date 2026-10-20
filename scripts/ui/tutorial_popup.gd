extends Control
## 场景：scenes/ui/tutorial_popup.tscn 玩法教程弹窗（全屏遮罩 + res://art/教程.png）。
##
## 由 main.tscn 右下角问号按钮打开；点任意处（遮罩/图片）或 ESC 关闭。
## 打开时暂停整棵场景树（波次在跑也先停住，看完教程不会被偷家），关闭只解除自己造的那次暂停。

signal closed

const SfxScript = preload("res://scripts/ui/sfx.gd")

var _paused_by_me := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()
	# 单独运行本场景（F6）时直接展示，方便调布局。
	if get_tree() != null and get_tree().current_scene == self:
		open()


func open() -> void:
	if visible:
		return
	show()
	SfxScript.play_if_exists("展开")
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true


func close() -> void:
	if not visible:
		return
	hide()
	SfxScript.play_if_exists("收起")
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## 点任意处关闭走 `_input`，不走 `_gui_input`：遮罩 Dim 与教程图（TextureRect）各自是
## MOUSE_FILTER_STOP，GUI 命中链在暂停态下不可靠（实测根节点收不到）。弹窗打开时全屏遮罩
## 本就该吞掉左键，用 `_input` 一次覆盖遮罩/图片/面板任何位置。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	_on_anywhere_input(event)


## 点任意处关闭（左键按下）。ESC 见 _unhandled_input。
func _on_anywhere_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()
