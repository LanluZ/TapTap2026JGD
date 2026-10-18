extends SceneTree
## headless 验证全局 CRT 扫描线滤镜（autoload CrtOverlay）：
## 注册项、CanvasLayer 层级、全屏 ColorRect 尺寸/位置、mouse_filter=IGNORE（不吞输入）、
## shader 材质与视觉参数（4px 周期 / 2px 暗线 / 0.35 不透明度）、运行时开关。
##
## 运行：
##   godot --headless --path <项目目录> -s res://tests/crt_overlay_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 注：`-s` 模式不实例化 autoload，故本脚本手动 new 出脚本挂到 root 验证；
##     shader 编译与观感（条纹疏密、文字可读性）由用户在实机确认，headless dummy 渲染器不编译 shader。

var _checks: int = 0
var _failures: int = 0
var _done: bool = false


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
	print("======== CRT 扫描线滤镜自检 ========")

	# 1) autoload 注册项
	var cfg := FileAccess.get_file_as_string("res://project.godot")
	_ok(cfg.contains('CrtOverlay="*res://scripts/ui/crt_overlay.gd"'),
		"project.godot 已注册 autoload CrtOverlay")

	# 2) 按 autoload 方式实例化并挂树（触发 _ready）
	var script: GDScript = load("res://scripts/ui/crt_overlay.gd")
	_ok(script != null, "crt_overlay.gd 可加载")
	if script == null:
		return _summary()
	var overlay: Node = script.new()
	root.add_child(overlay)

	_ok(overlay is CanvasLayer, "根节点是 CanvasLayer")
	var canvas := overlay as CanvasLayer
	_ok(canvas != null and canvas.layer == 100, "layer == 100（压在其它 CanvasLayer 之上）")

	# 3) 全屏覆盖层
	var rect := overlay.get_node_or_null("ScanlineRect") as ColorRect
	_ok(rect != null, "存在 ScanlineRect 子节点")
	if rect == null:
		overlay.free()
		return _summary()

	_ok(rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"mouse_filter == IGNORE（整屏覆盖不会吞掉 UI 点击）")
	var vp_size := root.get_visible_rect().size
	_ok(rect.position.is_equal_approx(Vector2.ZERO), "position == (0,0)")
	_ok(rect.size.is_equal_approx(vp_size), "size 等于视口逻辑尺寸 %s" % str(vp_size))
	print("    覆盖尺寸: %s / 视口: %s" % [str(rect.size), str(vp_size)])

	# 4) 材质与参数
	var mat := rect.material as ShaderMaterial
	_ok(mat != null, "ColorRect 挂载 ShaderMaterial")
	if mat == null:
		overlay.free()
		return _summary()
	var expected_shader: Shader = load("res://shaders/crt_scanline.gdshader")
	_ok(mat.shader == expected_shader, "shader == shaders/crt_scanline.gdshader")
	_ok(is_equal_approx(float(mat.get_shader_parameter("line_spacing")), 4.0), "line_spacing == 4.0")
	_ok(is_equal_approx(float(mat.get_shader_parameter("line_width")), 2.0), "line_width == 2.0")
	_ok(is_equal_approx(float(mat.get_shader_parameter("line_alpha")), 0.35), "line_alpha == 0.35")

	# 5) 运行时开关 / 强度调节（后续接设置面板的入口）
	overlay.set_scanlines_enabled(false)
	_ok(not overlay.visible, "set_scanlines_enabled(false) 隐藏覆盖层")
	overlay.set_scanlines_enabled(true)
	_ok(overlay.visible, "set_scanlines_enabled(true) 恢复显示")
	overlay.set_line_alpha(0.5)
	_ok(is_equal_approx(float(mat.get_shader_parameter("line_alpha")), 0.5), "set_line_alpha(0.5) 生效")
	overlay.set_line_alpha(2.0)
	_ok(is_equal_approx(float(mat.get_shader_parameter("line_alpha")), 1.0), "set_line_alpha 超界被钳到 1.0")

	overlay.free()
	return _summary()
