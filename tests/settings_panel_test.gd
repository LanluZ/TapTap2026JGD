extends SceneTree
## headless 验证设置面板（scenes/ui/settings_panel.tscn）与 main.tscn 集成：
## 独立场景可加载/实例化、必需节点与文案、默认隐藏、process_mode、
## open/close 与场景树暂停状态、ESC 关闭、两个按钮各自的信号与暂停恢复。
## 运行：godot --headless --path <项目目录> -s res://tests/settings_panel_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 注：遮罩浓度、居中、像素按钮观感、ESC 实机手感由用户在实机确认，本脚本不做视觉结论。

const SCENE_PATH := "res://scenes/ui/settings_panel.tscn"
const NODES: Array[String] = [
	"Dim",
	"Center",
	"Center/Panel",
	"Center/Panel/VBox/Title",
	"Center/Panel/VBox/Content",
	"Center/Panel/VBox/Buttons",
	"Center/Panel/VBox/Buttons/ResumeButton",
	"Center/Panel/VBox/Buttons/TitleButton",
]

var _checks := 0
var _failures := 0
var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_run())
	return true


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


func _summary() -> int:
	print("======== 汇总: %d 项检查, %d 项失败 ========" % [_checks, _failures])
	return _failures


func _run() -> int:
	print("======== 设置面板自检 ========")

	# 1) 独立场景
	var packed = load(SCENE_PATH)
	_ok(packed is PackedScene, "settings_panel.tscn 可加载")
	if not (packed is PackedScene):
		return _summary()
	var panel := (packed as PackedScene).instantiate()
	_ok(panel != null, "settings_panel.tscn 可实例化")
	if panel == null:
		return _summary()
	root.add_child(panel)

	# 2) 结构与文案
	for path in NODES:
		_ok(panel.get_node_or_null(path) != null, "节点存在: " + path)
	var title := panel.get_node_or_null("Center/Panel/VBox/Title") as Label
	var resume_btn := panel.get_node_or_null("Center/Panel/VBox/Buttons/ResumeButton") as Button
	var title_btn := panel.get_node_or_null("Center/Panel/VBox/Buttons/TitleButton") as Button
	_ok(title != null and title.text == "设置", "标题文案=设置")
	_ok(resume_btn != null and resume_btn.text == "返回游戏", "按钮文案=返回游戏")
	_ok(title_btn != null and title_btn.text == "返回标题", "按钮文案=返回标题")
	if resume_btn == null or title_btn == null:
		panel.queue_free()
		return _summary()

	# 3) 默认态与暂停语义
	_ok(not panel.visible, "默认隐藏（不遮挡关卡输入）")
	_ok(panel.get_node("Dim").mouse_filter == Control.MOUSE_FILTER_IGNORE, "遮罩不吞点击（面板自身拦截）")
	_ok(panel.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "process_mode=WHEN_PAUSED（暂停后仍收输入）")
	_ok(panel.get_content() != null, "get_content() 暴露设置项容器")

	# 4) open / ESC 关闭
	panel.open()
	_ok(panel.visible and panel.is_open(), "open() 后面板可见")
	_ok(paused, "open() 后场景树暂停")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	panel._unhandled_input(esc)
	_ok(not panel.visible, "ESC 关闭面板")
	_ok(not paused, "ESC 关闭后恢复运行")

	# 5) 两个按钮：信号 + 暂停复位
	var got := {"resume": 0, "title": 0}
	panel.resume_requested.connect(func() -> void: got["resume"] += 1)
	panel.title_requested.connect(func() -> void: got["title"] += 1)
	panel.open()
	resume_btn.pressed.emit()
	_ok(got["resume"] == 1, "「返回游戏」发 resume_requested")
	_ok(not panel.visible and not paused, "「返回游戏」关闭面板并恢复运行")
	panel.open()
	title_btn.pressed.emit()
	_ok(got["title"] == 1, "「返回标题」发 title_requested")
	_ok(not panel.visible and not paused, "「返回标题」关面板，暂停已解除（切场景不会带暂停进菜单）")
	_ok(got["resume"] == 1, "「返回标题」不误发 resume_requested")

	panel.queue_free()

	# 6) main.tscn 集成：实例在场景里，ESC 路径走 main_ui
	var main_packed = load("res://scenes/main.tscn")
	_ok(main_packed is PackedScene, "main.tscn 可加载")
	if not (main_packed is PackedScene):
		return _summary()
	var main := (main_packed as PackedScene).instantiate()
	root.add_child(main)
	var integrated := main.get_node_or_null("SettingsPanel")
	_ok(integrated != null, "main.tscn 内含 SettingsPanel 实例")
	_ok(not main.is_settings_open(), "关卡开局设置面板关闭")
	main.open_settings()
	_ok(main.is_settings_open() and paused, "open_settings() 打开发面板并暂停")
	integrated.get_node("Center/Panel/VBox/Buttons/ResumeButton").pressed.emit()
	_ok(not main.is_settings_open() and not paused, "关卡内「返回游戏」关闭面板并恢复")

	# ESC 走 main_ui._unhandled_input（无 DNA 弹窗时应打开设置）
	main._unhandled_input(esc)
	_ok(main.is_settings_open(), "关卡内 ESC 打开设置面板")
	integrated.get_node("Center/Panel/VBox/Buttons/ResumeButton").pressed.emit()
	_ok(not paused, "再次关闭后运行恢复")

	main.queue_free()
	return _summary()
