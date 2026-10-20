extends CanvasLayer
## 全局场景转场层（autoload 名 SceneTransition）：溶解遮罩盖屏 → 切场景 → 反向溶解揭开。
## 遮罩 = 全屏 ColorRect + shaders/scene_dissolve.gdshader（fbm 溶解 + 暖橙燃边，风格同 LOGO）。
## 调用方把 get_tree().change_scene_to_file(...) / reload_current_scene() 换成
## SceneTransition.change_scene(path) / SceneTransition.reload_scene() 即得转场。
## 切换过程中 _busy 挡住重复调用（连点按钮不会叠加两次转场）。

const DISSOLVE_SHADER := preload("res://shaders/scene_dissolve.gdshader")

## 高于 CrtOverlay(100)，转场时把 CRT 条纹也一起盖住，揭开后新场景重新叠滤镜。
const TRANSITION_LAYER := 110

## 单程时长（秒）：盖屏 0.4s + 揭开 0.4s。
const DURATION := 0.4

## 遮罩可见时不吞输入（按钮连点由 _busy 挡），淡入淡出交给 shader 的 alpha。
var _rect: ColorRect
var _material: ShaderMaterial
var _busy := false


func _ready() -> void:
	layer = TRANSITION_LAYER
	# 设置面板会 pause 整棵树，转场必须照常跑（否则"返回标题"卡死在黑屏）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = DISSOLVE_SHADER
	_material.set_shader_parameter("progress", 0.0)
	_rect = ColorRect.new()
	_rect.name = "DissolveRect"
	_rect.material = _material
	_rect.color = Color.WHITE # 颜色/透明度全由 shader 输出决定
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# FULL_RECT anchors 直挂 CanvasLayer 时以视口为父矩形，窗口拉伸/全屏切换自动跟随，无需手动 fit。
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## 转场切场景：溶解盖屏 → change_scene_to_file → 反向溶解揭开新场景。
func change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true
	await _cover()
	get_tree().change_scene_to_file(path)
	await _reveal()


## 转场重载当前场景（结算面板"重新开始"用）。调用前照旧自行设置 pending_level_id。
func reload_scene() -> void:
	if _busy:
		return
	_busy = true
	await _cover()
	get_tree().reload_current_scene()
	await _reveal()


func _cover() -> void:
	await _tween_to(1.0)


func _reveal() -> void:
	await _tween_to(0.0)
	_busy = false


func _tween_to(target: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_progress, _material.get_shader_parameter("progress") as float, target, DURATION)
	await tw.finished


func _set_progress(v: float) -> void:
	_material.set_shader_parameter("progress", v)

