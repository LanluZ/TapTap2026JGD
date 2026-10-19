extends SceneTree
## headless 验证主菜单背景板（scenes/menu.tscn 的 Camera3D/Background）：
## 节点挂在相机下、铺满视锥截面、材质不受光、UI 层不再有全屏贴图压住 3D 背景。
## 运行：godot --headless --path <项目目录> -s res://tests/menu_background_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 注：背景遮挡关系、构图观感由用户在实机确认，本脚本不做视觉结论。

const SCENE_PATH := "res://scenes/menu.tscn"
const BG_DISTANCE := 10.0

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
	print("[menu_background_test]")
	var menu: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(menu)

	var cam: Camera3D = menu.get_node_or_null("Camera3D")
	var bg: MeshInstance3D = menu.get_node_or_null("Camera3D/Background")
	_ok(cam != null, "Camera3D 存在")
	_ok(bg != null, "Camera3D/Background 存在（背景板挂在相机下，随相机浮动）")

	if cam == null or bg == null:
		menu.queue_free()
		print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
		return _failures

	_ok(is_equal_approx(bg.position.z, -BG_DISTANCE), "背景板位于相机前方 %.0f 单位" % BG_DISTANCE)

	var quad: QuadMesh = bg.mesh as QuadMesh
	_ok(quad != null, "背景板 mesh 为 QuadMesh")
	if quad != null:
		var vp: Vector2 = root.get_visible_rect().size
		var expect_h: float = 2.0 * BG_DISTANCE * tan(deg_to_rad(cam.fov) * 0.5)
		var expect_w: float = expect_h * vp.x / maxf(vp.y, 1.0)
		_ok(is_equal_approx(quad.size.y, expect_h), "板高 = 视锥截面高 %.4f（实际 %.4f）" % [expect_h, quad.size.y])
		_ok(is_equal_approx(quad.size.x, expect_w), "板宽 = 视锥截面宽 %.4f（实际 %.4f）" % [expect_w, quad.size.x])

	var mat: StandardMaterial3D = bg.get_surface_override_material(0) as StandardMaterial3D
	_ok(mat != null, "背景板挂了 StandardMaterial3D")
	if mat != null:
		_ok(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "材质 unshaded（不受场景灯光影响）")
		_ok(mat.albedo_texture != null, "材质带背景贴图")

	var ui: Control = menu.get_node_or_null("UI")
	_ok(ui != null, "UI 层存在")
	if ui != null:
		var full_rect_sprites := 0
		for child in ui.get_children():
			if child is Sprite2D and (child as Sprite2D).texture != null:
				if (child as Sprite2D).get_rect().size.x >= 1280.0:
					full_rect_sprites += 1
		_ok(full_rect_sprites == 0, "UI 层没有全屏 Sprite2D 贴图（不会盖住 3D 背景）")

	menu.queue_free()
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	return _failures
