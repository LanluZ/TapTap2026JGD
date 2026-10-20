extends SceneTree
## 多地图数据校验（headless）：三张关卡地图可加载、路径闭合连通、构建区不压路径、
## 起手卡与卡池自洽。只做非视觉检查。
##
## 运行：godot --headless --path <项目目录> -s res://tests/levels_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const LEVELS := [&"level_1", &"level_2", &"level_3"]

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _init() -> void:
	var code := _run()
	_finished = true
	quit(code)


func _process(_dt: float) -> bool:
	return _finished


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


func _run() -> int:
	print("======== 多地图数据校验 ========")
	var config = GameConfig.load_all()
	_ok(config != null, "GameConfig.load_all() 成功")
	if config == null:
		return 1

	for lid in LEVELS:
		_ok(config.levels.has(lid), "关卡存在 %s" % String(lid))
	if _failures > 0:
		return _failures

	for lid in LEVELS:
		var lv: Dictionary = config.get_level(lid)
		var tag := "%s「%s」" % [String(lid), String(lv.get("name", ""))]

		# 1. 世界可构建（RingPath 闭合、11 系统 setup）
		var world = BootstrapScript.build_world(config, lid)
		_ok(world != null, "%s 世界构建成功" % tag)
		if world == null:
			continue

		# 2. 路径连通：相邻格曼哈顿距离 1，首尾相接
		var path_cells: Array = lv["path_cells"]
		var broken := 0
		for i in path_cells.size():
			var a: Vector2i = path_cells[i]
			var b: Vector2i = path_cells[(i + 1) % path_cells.size()]
			if absi(a.x - b.x) + absi(a.y - b.y) != 1:
				broken += 1
		_ok(broken == 0, "%s 路径闭合且相邻（%d 格，断开 %d）" % [tag, path_cells.size(), broken])

		# 3. 建造区不压路径
		var path_set := {}
		for c in path_cells:
			path_set[c] = true
		var overlap := 0
		for c in lv["buildable_cells"]:
			if path_set.has(c):
				overlap += 1
		_ok(overlap == 0, "%s 建造区 %d 格与路径无重叠" % [tag, lv["buildable_cells"].size()])

		# 4. 网格已按关卡标注：路径格不可建造、建造格可建造
		var bad_flag := 0
		for c in path_cells:
			var cell = world.grid.get_cell(c)
			if cell == null or cell.buildable:
				bad_flag += 1
		for c in lv["buildable_cells"]:
			var cell2 = world.grid.get_cell(c)
			if cell2 == null or not cell2.buildable:
				bad_flag += 1
		_ok(bad_flag == 0, "%s 网格标注正确（错标 %d）" % [tag, bad_flag])

		# 5. 起手卡：数量 = hand_start，顺序 = hand_start_cards，且都在卡池内
		var hand: Array = world.get_system("CardSystem").deck.hand
		var fixed: Array = lv.get("hand_start_cards", [])
		_ok(hand.size() == int(lv["hand_start"]), "%s 起手 %d 张（hand_start=%d）" % [tag, hand.size(), int(lv["hand_start"])])
		var order_ok := hand.size() >= fixed.size()
		for i in mini(hand.size(), fixed.size()):
			if str(hand[i]) != str(fixed[i]):
				order_ok = false
		_ok(order_ok, "%s 起手顺序符合 hand_start_cards" % tag)
		var not_in_pool := 0
		for cid in fixed:
			if not (lv["card_pool"] as Array).has(str(cid)):
				not_in_pool += 1
		_ok(not_in_pool == 0, "%s 起手卡都在卡池内" % tag)

		# 6. 预置地块类型已定义
		var tile_ok := true
		for t in lv["tiles"]:
			if not (lv["tile_types"] as Dictionary).has(StringName(str(t["tile_type"]))):
				tile_ok = false
		_ok(tile_ok, "%s 预置地块类型均已定义" % tag)

		# 7. 波次敌人均已定义
		var enemy_bad := 0
		for w in lv["waves"]:
			for s in (w as Dictionary)["spawns"]:
				if not config.enemies.has(StringName(str(s["enemy"]))):
					enemy_bad += 1
		_ok(enemy_bad == 0, "%s 波次敌人均已定义（%d 波）" % [tag, (lv["waves"] as Array).size()])

		# 8. 关卡级字段：开局零件按产品裁定锁值（14/26/34；改关卡数值必须同步本条）
		var want_parts := {&"level_1": 14, &"level_2": 26, &"level_3": 34}
		var parts0 := int(lv["start_resources"].get("parts", 0))
		_ok(parts0 == int(want_parts[lid]),
			"%s 开局零件 = %d（期望 %d）" % [tag, parts0, int(want_parts[lid])])

	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	return _failures
