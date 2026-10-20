extends SceneTree
## headless 验证全局溶解转场层（autoload SceneTransition）：
## project.godot 注册项、CanvasLayer 层级（110 > CrtOverlay 100）、全屏 ColorRect 尺寸、
## mouse_filter=IGNORE（不吞输入）、溶解 shader 材质与 progress 参数初值，
## 以及 change_scene 转场全流程：遮罩盖屏 → 切场景 → 揭开复位（progress 回 0、_busy 解除）。
##
## 运行：
##   godot --headless --path <项目目录> -s res://tests/scene_transition_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 注：`-s` 模式不实例化 autoload，故本脚本手动 new 出脚本挂到 root 验证；
##     shader 编译与观感（溶解碎块疏密、燃边亮度）由用户实机确认，headless dummy 渲染器不编译 shader。

const SCRIPT_PATH := "res://scripts/ui/scene_transition.gd"
const TARGET_SCENE := "res://scenes/menu.tscn"

var _checks: int = 0
var _failures: int = 0
var _st: CanvasLayer = null
var _frames: int = 0


func _process(_dt: float) -> bool:
	# 多帧流程：第 0 帧静态检查并发起转场，之后等转场跑完再收尾。
	if _frames == 0:
		_st = _static_checks()
		if _st == null:
			quit(_failures)
			return true
		_st.change_scene(TARGET_SCENE)
	elif _st != null and (not _st._busy or _frames > 300):
		_dynamic_checks()
		quit(_failures)
		return true
	_frames += 1
	return false


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		print("  [FAIL] " + label)


## 静态检查 + 挂树（触发 _ready）。返回挂好的节点，失败返回 null。
func _static_checks() -> CanvasLayer:
	print("[scene_transition_test]")
	# 1) autoload 注册项
	var cfg := ConfigFile.new()
	_ok(cfg.load("res://project.godot") == OK, "project.godot 可读")
	_ok(cfg.has_section_key("autoload", "SceneTransition")
		and str(cfg.get_value("autoload", "SceneTransition")) == "*res://scripts/ui/scene_transition.gd",
		"project.godot 已注册 autoload SceneTransition")

	# 2) 按 autoload 方式实例化并挂树（触发 _ready）
	var script := load(SCRIPT_PATH) as GDScript
	_ok(script != null, "scene_transition.gd 可加载")
	if script == null:
		return null
	var st := script.new() as CanvasLayer
	root.add_child(st)

	# 3) 层级与遮罩
	_ok(st.layer > 100, "转场层 layer=%d 高于 CrtOverlay(100)" % st.layer)
	var rect := st.get_node_or_null("DissolveRect") as ColorRect
	_ok(rect != null, "全屏遮罩 DissolveRect 已创建")
	if rect == null:
		return st
	_ok(rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "遮罩 mouse_filter=IGNORE（不吞输入）")
	var vp_size := (root.get_viewport() as Viewport).get_visible_rect().size
	_ok(rect.size.is_equal_approx(vp_size), "遮罩尺寸跟随视口 %s" % vp_size)
	_ok(rect.material is ShaderMaterial, "遮罩挂 ShaderMaterial")
	var mat := rect.material as ShaderMaterial
	_ok(mat.shader != null and mat.shader.get_path() == "res://shaders/scene_dissolve.gdshader",
		"材质使用 scene_dissolve.gdshader")
	_ok(is_equal_approx(float(mat.get_shader_parameter("progress")), 0.0), "progress 初始为 0（全透明）")
	_ok(st.process_mode == Node.PROCESS_MODE_ALWAYS, "process_mode=ALWAYS（暂停树下转场照跑）")
	_ok(not st._busy, "初始 _busy=false")
	return st


## 转场跑完后的动态断言（change_scene 内部已 await 到揭开结束）。
func _dynamic_checks() -> void:
	_ok(not _st._busy, "转场结束后 _busy 解除")
	_ok(current_scene != null and current_scene.scene_file_path == TARGET_SCENE,
		"已切换到 %s" % TARGET_SCENE)
	var rect := _st.get_node_or_null("DissolveRect") as ColorRect
	if rect != null:
		var mat := rect.material as ShaderMaterial
		_ok(is_equal_approx(float(mat.get_shader_parameter("progress")), 0.0),
			"揭开后 progress 回到 0（遮罩透明，不挡新场景）")
