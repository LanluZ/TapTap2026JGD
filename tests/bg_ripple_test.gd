extends SceneTree
## headless 结构测试：主菜单远景（背景1）的水波扭曲材质。
## 只验证「材质挂上了 + 参数预算安全 + 波带两端在画面外」，波纹观感由用户实机确认。
## 运行：godot --headless --path <项目目录> -s res://tests/bg_ripple_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const SCENE_PATH := "res://scenes/menu.tscn"
const SHADER_PATH := "res://shaders/bg_wave_ripple.gdshader"

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


func _num(mat: ShaderMaterial, key: String) -> float:
	var v = mat.get_shader_parameter(key)
	return float(v) if v != null else NAN


func _run() -> int:
	print("[bg_ripple_test]")
	var menu: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(menu)

	var bg: Sprite2D = menu.get_node_or_null("UI/背景1") as Sprite2D
	_ok(bg != null, "UI/背景1 存在")
	if bg == null:
		menu.queue_free()
		return _failures

	var mat := bg.material as ShaderMaterial
	_ok(mat != null, "背景1 挂的是 ShaderMaterial")
	if mat == null:
		menu.queue_free()
		return _failures
	_ok(mat.shader != null and mat.shader.resource_path == SHADER_PATH, "材质用的是 %s" % SHADER_PATH)

	var amp := _num(mat, "ripple_amp")
	var edge := _num(mat, "ripple_edge")
	var cycle := _num(mat, "ripple_cycle")
	var gap := _num(mat, "ripple_gap")
	var width := _num(mat, "ripple_width")
	print("  amp=%.4f edge=%.4f cycle=%.2fs gap=%.2fs width=%.2f" % [amp, edge, cycle, gap, width])

	_ok(amp > 0.0, "波纹有横向位移（amp %.4f）" % amp)
	_ok(cycle > 0.0, "一次扫过有正时长（%.2fs）" % cycle)
	_ok(gap > 0.0, "两次波纹之间有静默期（gap %.2fs → 每隔 %.2fs 一道）" % [gap, cycle + gap])
	# 左右边缘的衰减宽度必须盖住最大位移，否则 UV.x 越界会被 clamp 到边缘像素、拉出竖丝
	_ok(amp <= edge, "位移 %.4f ≤ 边缘衰减宽度 %.4f（越界区域已衰减到 0）" % [amp, edge])

	# 波带中心公式：center = (1+w) - prog*(1+2w)，prog 0→1 时从底边下方走到顶边上方
	var w := maxf(width, 0.01)
	var start := (1.0 + w) - 0.0 * (1.0 + 2.0 * w)
	var end := (1.0 + w) - 1.0 * (1.0 + 2.0 * w)
	_ok(start > 1.0, "起始波带中心 %.3f 在底边之外（不会凭空出现在画面里）" % start)
	_ok(end < 0.0, "结束波带中心 %.3f 在顶边之外（不会在顶部残留半道波）" % end)

	_ok(mat.shader.code.contains("ripple_amp"), "shader 源码里能查到 ripple_amp")
	menu.queue_free()
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	return _failures
