extends SceneTree
## headless 验证菜单设置界面（scenes/ui/menu_settings.tscn）与教程弹窗（scenes/ui/tutorial_popup.tscn）：
## 两个场景可加载/实例化、默认隐藏、必需节点与文案、音量滑块真的改到 Bgm/Sfx 单例、
## 关闭路径（按钮/ESC）、main.tscn 右下角问号按钮的锚点与尺寸、menu.tscn 里「设置」按钮接线。
## 运行：godot --headless --path <项目目录> -s res://tests/menu_settings_tutorial_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 注：面板观感、滑块手感、教程图清晰度由用户在实机确认，本脚本不做视觉结论。

const MENU_SETTINGS := "res://scenes/ui/menu_settings.tscn"
const TUTORIAL := "res://scenes/ui/tutorial_popup.tscn"

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
	print("======== 菜单设置 + 教程弹窗自检 ========")
	_check_menu_settings()
	_check_tutorial()
	_check_main_integration()
	_check_menu_integration()
	return _summary()


## 1) 菜单设置界面：结构、默认态、两条滑块真的改到单例、关闭路径
func _check_menu_settings() -> void:
	var packed = load(MENU_SETTINGS)
	_ok(packed is PackedScene, "menu_settings.tscn 可加载")
	if not (packed is PackedScene):
		return
	var panel := (packed as PackedScene).instantiate()
	root.add_child(panel)

	for path in [
		"Dim",
		"Center/Frame/VBox/Title",
		"Center/Frame/VBox/BGMRow/Box/Slider",
		"Center/Frame/VBox/SfxRow/Box/Slider",
		"Center/Frame/VBox/Buttons/CloseButton",
	]:
		_ok(panel.get_node_or_null(path) != null, "节点存在: " + path)

	var title := panel.get_node_or_null("Center/Frame/VBox/Title") as Label
	_ok(title != null and title.text == "设置", "标题文案=设置")
	_ok(not panel.visible, "作为子节点时默认隐藏")

	var bgm_slider := panel.get_node_or_null("Center/Frame/VBox/BGMRow/Box/Slider") as HSlider
	var sfx_slider := panel.get_node_or_null("Center/Frame/VBox/SfxRow/Box/Slider") as HSlider
	var bgm_label := panel.get_node_or_null("Center/Frame/VBox/BGMRow/Box/Value") as Label
	var sfx_label := panel.get_node_or_null("Center/Frame/VBox/SfxRow/Box/Value") as Label
	_ok(bgm_slider != null and bgm_slider.value == 80.0, "BGM 滑块默认 80（与默认音量一致）")
	_ok(sfx_slider != null and sfx_slider.value == 80.0, "音效滑块默认 80")
	_ok(bgm_label != null and bgm_label.text == "80%", "BGM 数值文案=80%")

	# 滑块写入单例：autoload 在 -s 下同样实例化
	var bgm := root.get_node_or_null("Bgm")
	var sfx := root.get_node_or_null("Sfx")
	_ok(bgm != null, "autoload Bgm 在场")
	_ok(sfx != null, "autoload Sfx 在场")
	if bgm_slider == null or sfx_slider == null or bgm == null or sfx == null:
		panel.queue_free()
		return
	bgm_slider.value = 35.0
	sfx_slider.value = 0.0
	_ok(abs(float(bgm.get_volume()) - 0.35) < 0.001, "拖 BGM 滑块 → Bgm 音量 0.35（实测 %.3f）" % bgm.get_volume())
	_ok(abs(float(sfx.get_volume()) - 0.0) < 0.001, "拖音效滑块到 0 → 静音（实测 %.3f）" % sfx.get_volume())
	_ok(bgm_label.text == "35%" and sfx_label.text == "0%", "数值文案跟随滑块")

	# 打开 / 关闭
	var closes := [0]
	panel.closed.connect(func() -> void: closes[0] += 1)
	panel.open()
	_ok(panel.visible and panel.is_open(), "open() 后可见")
	panel.get_node("Center/Frame/VBox/Buttons/CloseButton").pressed.emit()
	_ok(not panel.visible and closes[0] == 1, "「关闭」按钮收起并发 closed")

	panel.open()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	panel._unhandled_input(esc)
	_ok(not panel.visible and closes[0] == 2, "ESC 收起并发 closed")
	_ok(not paused, "菜单设置不暂停场景树")

	panel.queue_free()


## 2) 教程弹窗：教程图接对、打开即暂停、关闭解除暂停
func _check_tutorial() -> void:
	var packed = load(TUTORIAL)
	_ok(packed is PackedScene, "tutorial_popup.tscn 可加载")
	if not (packed is PackedScene):
		return
	var popup := (packed as PackedScene).instantiate()
	root.add_child(popup)

	_ok(not popup.visible, "教程弹窗默认隐藏")
	var image := popup.get_node_or_null("Center/Frame/VBox/Image") as TextureRect
	_ok(image != null, "教程图节点存在")
	_ok(image != null and image.texture != null, "教程贴图已加载（res://art/教程.png）")
	if image != null and image.texture != null:
		_ok(image.texture.resource_path == "res://art/教程.png", "贴图路径=教程.png（实测 %s）" % image.texture.resource_path)
		var tex_size := image.texture.get_size()
		_ok(tex_size.x > 0.0 and tex_size.y > 0.0, "教程图尺寸有效（%dx%d）" % [int(tex_size.x), int(tex_size.y)])
	var hint := popup.get_node_or_null("Center/Frame/VBox/Hint") as Label
	_ok(hint != null and hint.text.contains("关闭"), "底注含关闭提示（实测 %s）" % (hint.text if hint != null else "nil"))

	var closes := [0]
	popup.closed.connect(func() -> void: closes[0] += 1)
	popup.open()
	_ok(popup.visible and popup.is_open(), "open() 后可见")
	_ok(paused, "打开教程时暂停（波次不会偷家）")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	popup._unhandled_input(esc)
	_ok(not popup.visible and closes[0] == 1, "ESC 收起并发 closed")
	_ok(not paused, "关闭后解除暂停")

	popup.open()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	popup._on_anywhere_input(click)
	_ok(not popup.visible and not paused, "点任意处关闭并恢复运行")

	popup.queue_free()


## 3) main.tscn：问号按钮在右下角（锚点 1,1 + 64x64）、接线打通、弹窗实例在场景里
func _check_main_integration() -> void:
	var packed = load("res://scenes/main.tscn")
	_ok(packed is PackedScene, "main.tscn 可加载")
	if not (packed is PackedScene):
		return
	var main := (packed as PackedScene).instantiate()
	root.add_child(main)

	var btn := main.get_node_or_null("TutorialButton") as Button
	var popup := main.get_node_or_null("TutorialPopup")
	_ok(btn != null, "main.tscn 含 TutorialButton")
	_ok(popup != null, "main.tscn 含 TutorialPopup 实例")
	if btn == null or popup == null:
		main.queue_free()
		return
	_ok(btn.text == "?", "按钮文案=?")
	_ok(btn.anchor_left == 1.0 and btn.anchor_top == 1.0 and btn.anchor_right == 1.0 and btn.anchor_bottom == 1.0,
		"按钮锚在右下角（anchor=%s/%s）" % [btn.anchor_left, btn.anchor_top])
	_ok(btn.offset_left == -92.0 and btn.offset_top == -92.0 and btn.offset_right == -28.0 and btn.offset_bottom == -28.0,
		"距右下各 28px、尺寸 64x64（offset=%s,%s,%s,%s）" % [btn.offset_left, btn.offset_top, btn.offset_right, btn.offset_bottom])
	_ok(abs(btn.size.x - 64.0) < 0.5 and abs(btn.size.y - 64.0) < 0.5,
		"按钮实测尺寸 64x64（实测 %.1fx%.1f）" % [btn.size.x, btn.size.y])
	_ok(main.has_method("open_tutorial") and not main.is_tutorial_open(), "对外 open_tutorial / is_tutorial_open 就绪且初始关闭")

	btn.pressed.emit()
	_ok(main.is_tutorial_open(), "点问号 → 教程弹窗打开")
	popup.close()
	_ok(not main.is_tutorial_open() and not paused, "关闭教程后恢复")

	main.queue_free()


## 4) menu.tscn：「设置」按钮第一次点 → 懒加载出菜单设置界面并打开
func _check_menu_integration() -> void:
	var packed = load("res://scenes/menu.tscn")
	_ok(packed is PackedScene, "menu.tscn 可加载")
	if not (packed is PackedScene):
		return
	var menu := (packed as PackedScene).instantiate()
	root.add_child(menu)

	var btn := menu.get_node_or_null("UI/CenterContainer/MenuPanel/VBox/SettingsButton") as Button
	_ok(btn != null, "menu.tscn 含 SettingsButton")
	if btn == null:
		menu.queue_free()
		return
	_ok(menu.get_node_or_null("UI/MenuSettings") == null, "初始没有菜单设置实例（懒加载）")
	btn.pressed.emit()
	var panel := menu.get_node_or_null("UI/MenuSettings")
	_ok(panel != null, "点「设置」后实例化 MenuSettings")
	if panel != null:
		_ok(panel.visible, "菜单设置界面已打开")
		panel.close()
		_ok(not panel.visible, "关闭后隐藏")
	btn.pressed.emit()
	_ok(panel != null and panel.visible, "再点「设置」复用同一实例并重开")
	if panel != null:
		panel.close()

	menu.queue_free()
