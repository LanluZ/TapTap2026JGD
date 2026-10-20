extends SceneTree
## 运行：godot --headless --path <项目目录> -s res://tests/level_select_test.gd
## 覆盖 scenes/ui/level_select.tscn：三卡槽位内容、切档、点击中心卡发出 level_chosen、返回发出 closed。
## 只做数据/几何断言，观感交用户实测。

const SCENE_PATH := "res://scenes/ui/level_select.tscn"
const ConfigScript = preload("res://scripts/config/game_config.gd")

var _fails := 0
var _checks := 0


func _process(_dt: float) -> bool:
	quit(_run())
	return true


func _run() -> int:
	print("[level_select_test]")
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		print("  FAIL 场景加载失败")
		return 1
	var picker: Control = scene.instantiate() as Control
	root.add_child(picker)
	var config = ConfigScript.load_all()
	picker.setup(config)

	var ids: Array = picker.get("_ids")
	_eq(ids.size(), 3, "关卡数 = 3")
	_eq(str(ids[0]), "level_1", "顺序按 id 字符串排，首关 level_1")

	var cards: Array = picker.get("_cards")
	# 中央卡 = 槽位 1，侧卡 0/2
	var center: PanelContainer = cards[1]
	var left: PanelContainer = cards[0]
	var right: PanelContainer = cards[2]
	_eq(center.get_node("VBox/Name").text, "环谷要塞", "中央卡显示当前关名")
	_eq(left.get_node("VBox/Name").text, "折返双廊", "左卡回绕到最后一关")
	_eq(right.get_node("VBox/Name").text, "长峡回廊", "右卡是下一关")

	var tex_c: Texture2D = center.get_node("VBox/Shot").texture
	var tex_r: Texture2D = right.get_node("VBox/Shot").texture
	_ok(tex_c != null and tex_c.resource_path.ends_with("art/maps/0.png"), "中央卡载入 art/maps/0.png")
	_ok(tex_r != null and tex_r.resource_path.ends_with("art/maps/1.png"), "右卡载入 art/maps/1.png")

	_ok(center.size.x > left.size.x and center.size.y > left.size.y, "中央卡大于侧卡")
	var center_right := center.position.x + center.size.x
	const STAGE_W := 1200.0
	_ok(left.position.x < center.position.x and left.position.x + left.size.x > center.position.x,
		"左卡越过中央卡左缘（可见 %.0f px）" % (center.position.x - maxf(left.position.x, 0.0)))
	_ok(right.position.x > center.position.x and right.position.x + right.size.x > center_right,
		"右卡越过中央卡右缘（可见 %.0f px）" % (minf(right.position.x + right.size.x, STAGE_W) - center_right))

	# 切到下一关：中央卡换成 level_2 的图与名字
	picker.call("_step", 1)
	_eq(center.get_node("VBox/Name").text, "长峡回廊", "切换到下一关后中央卡换名")
	var tex_after: Texture2D = center.get_node("VBox/Shot").texture
	_ok(tex_after != null and tex_after.resource_path.ends_with("art/maps/1.png"), "切换后中央卡载入 art/maps/1.png")
	_eq(left.get_node("VBox/Name").text, "环谷要塞", "左卡变为上一关")

	# 点击中央卡 = 开始该关
	var chosen: Array = []
	picker.level_chosen.connect(func(lid): chosen.append(str(lid)))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	center.emit_signal("gui_input", click)
	_eq(chosen.size(), 1, "点击中央卡发出一次 level_chosen")
	_eq(chosen[0] if chosen.size() > 0 else "", "level_2", "发出的关卡与当前中央卡一致")

	# 点右卡 = 翻页，不发选关
	var before := int(picker.get("_index"))
	right.emit_signal("gui_input", click)
	_eq(int(picker.get("_index")), (before + 1) % 3, "点侧卡只翻页")
	_eq(chosen.size(), 1, "点侧卡不触发选关")

	var closed_count: Array = []
	picker.closed.connect(func(): closed_count.append(1))
	picker.call("_on_back")
	_eq(closed_count.size(), 1, "返回发出 closed")

	picker.queue_free()
	print("  汇总: 通过 %d / %d" % [_checks - _fails, _checks])
	return 0 if _fails == 0 else 1


func _eq(got, want, label: String) -> void:
	_checks += 1
	if got == want:
		print("  PASS %s（%s）" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %s：期望 %s，实得 %s" % [label, str(want), str(got)])


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS %s" % label)
	else:
		_fails += 1
		print("  FAIL %s" % label)
