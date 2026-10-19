extends SceneTree
## headless 护栏测试：主菜单三层背景视差的「位移预算」。
## 背景不给相机跟随而直接移动 Sprite，位移超过贴图超出视口的余量就会露出底边/黑边，
## 所以这里只验证位移上限，观感（跟手程度、摇摆幅度是否合适）由用户实机确认。
## 运行：godot --headless --path <项目目录> -s res://tests/menu_parallax_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const SCENE_PATH := "res://scenes/menu.tscn"
const FRAMES := 120

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
		print("  [FAIL] " + label)


func _run() -> int:
	print("[menu_parallax_test]")
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		print("  [FAIL] 场景加载失败")
		return 1
	var menu: Node = scene.instantiate()
	root.add_child(menu)

	var consts: Dictionary = menu.get_script().get_script_constant_map()
	var max_move: Vector2 = consts["PARALLAX_MAX"]
	var layers: Array = consts["PARALLAX_LAYERS"]
	_ok(layers.size() >= 3, "视差层配置 %d 层（≥3）" % layers.size())

	var nodes: Array = menu.get("_bg_nodes")
	var bases: Array = menu.get("_bg_base")
	_ok(nodes.size() == layers.size(), "_ready 已收集全部层节点（%d/%d）" % [nodes.size(), layers.size()])

	# headless 下 root 视口尺寸不可靠（实测 1600x1600），以项目设定的设计分辨率作为基准
	var vp := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	print("  视口基准 %.0fx%.0f" % [vp.x, vp.y])
	var prev_factor := -1.0
	for i in mini(nodes.size(), layers.size()):
		var sp: Sprite2D = nodes[i]
		var cfg: Dictionary = layers[i]
		var name := String(cfg["node"])
		_ok(sp != null, "%s 节点存在" % name)
		if sp == null:
			continue
		var tex := sp.texture
		_ok(tex != null, "%s 有贴图" % name)
		if tex == null:
			continue
		var drawn := tex.get_size() * sp.scale
		var slack := (drawn - vp) * 0.5
		var factor := float(cfg["factor"])
		var sway := float(cfg["sway_px"])
		var worst := Vector2(max_move.x * factor + sway, max_move.y * factor)
		_ok(worst.x <= slack.x, "%s 水平位移 %.1fpx ≤ 余量 %.1fpx" % [name, worst.x, slack.x])
		_ok(worst.y <= slack.y, "%s 垂直位移 %.1fpx ≤ 余量 %.1fpx" % [name, worst.y, slack.y])
		_ok(factor > prev_factor, "%s factor %.2f 比上一层大（近层动得多）" % [name, factor])
		prev_factor = factor

	# 跑一段时间，确认实际 position 始终落在预算内（含指针极端位置与摇摆峰值）
	var overflow := 0.0
	for _f in FRAMES:
		menu._process(1.0 / 60.0)
		for i in mini(nodes.size(), layers.size()):
			var sp: Sprite2D = nodes[i]
			if sp == null:
				continue
			var cfg: Dictionary = layers[i]
			var drawn := sp.texture.get_size() * sp.scale
			var slack := (drawn - vp) * 0.5
			var delta: Vector2 = sp.position - (bases[i] as Vector2)
			overflow = maxf(overflow, absf(delta.x) - slack.x)
			overflow = maxf(overflow, absf(delta.y) - slack.y)
	_ok(overflow <= 0.0001, "%d 帧内实际位移未超出余量（越界 %.2fpx）" % [FRAMES, maxf(overflow, 0.0)])

	menu.queue_free()
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	return _failures
