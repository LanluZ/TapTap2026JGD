## 全局：CRT 扫描线条纹滤镜（autoload 名 CrtOverlay）。
## 作用：在 layer=100 的 CanvasLayer 上铺一张全屏 ColorRect，用 res://shaders/crt_scanline.gdshader
## 画水平暗线，菜单/关卡/后续新场景自动生效，覆盖整屏（游戏画面 + HUD/UI）。
## 纯叠加，不采样屏幕纹理，无额外渲染 pass。
extends CanvasLayer

const SCANLINE_SHADER := preload("res://shaders/crt_scanline.gdshader")

## 叠在其它 CanvasLayer（dna_inspector 等默认 1）之上，保证滤镜在整屏最上层。
const OVERLAY_LAYER := 100

## 视觉参数（中等强度：每 4 像素一条、暗线宽 2 像素、不透明度 0.35）。
## 想在代码里临时调，改 _material.set_shader_parameter(...) 即可。
const LINE_SPACING := 4.0
const LINE_WIDTH := 2.0
const LINE_ALPHA := 0.25

var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = OVERLAY_LAYER
	_build_rect()
	_attach_viewport_hook()


## 全屏 ColorRect + 条纹材质。mouse_filter 必须 IGNORE：
## 否则这层盖在所有 UI 之上，会吞掉全部点击（按钮、拖拽全失效）。
func _build_rect() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SCANLINE_SHADER
	_material.set_shader_parameter("line_spacing", LINE_SPACING)
	_material.set_shader_parameter("line_width", LINE_WIDTH)
	_material.set_shader_parameter("line_alpha", LINE_ALPHA)

	_rect = ColorRect.new()
	_rect.name = "ScanlineRect"
	_rect.material = _material
	_rect.color = Color(1, 1, 1, 1)  # 颜色由 shader 输出决定，这里只需不透明以参与绘制
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_fit_viewport()


## 跟随视口尺寸（窗口拉伸/全屏切换）：stretch=canvas_items 时取到的是逻辑分辨率 1600x900。
func _attach_viewport_hook() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_viewport):
		vp.size_changed.connect(_fit_viewport)


func _fit_viewport() -> void:
	if _rect == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	_rect.position = Vector2.ZERO
	_rect.size = vp.get_visible_rect().size


## 运行时开关（后续接设置面板用）：false 时整层隐藏，不产生绘制开销。
func set_scanlines_enabled(enabled: bool) -> void:
	visible = enabled


func set_line_alpha(alpha: float) -> void:
	if _material != null:
		_material.set_shader_parameter("line_alpha", clampf(alpha, 0.0, 1.0))
