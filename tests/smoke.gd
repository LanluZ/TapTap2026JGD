extends SceneTree
## headless 最小验证脚本（架构文档 §12）：
## 加载配置 → 构建世界（§5 固定顺序 11 系统）→ 跑 tick → 断言。
##
## 运行：
##   godot --headless --path <项目目录> -s res://tests/smoke.gd
## 断言覆盖：实体创建/销毁、敌人沿路径推进并计圈、波次完成判定、
##           敌人数超上限判败、配方产出与欠料停产（+ 指令/卡牌/光环/击杀入账）。
## 退出码：0 = 全部通过；非 0 = 失败项数。

const DT := 0.1 # 逻辑步长（秒），与断言预算配套

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _init() -> void:
	var code := _run()
	_finished = true
	quit(code)


## 兜底：若 quit() 在 _init 阶段未生效，首个逻辑帧强制退出。
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
	print("======== 2026TAPTAP ECS 冒烟测试 ========")

	print("== T0: 配置加载与校验 ==")
	var config = GameConfig.load_all()
	_ok(config != null, "GameConfig.load_all() 成功（7 个 JSON 全部通过校验）")
	if config == null:
		printerr("配置加载失败，后续测试无法进行")
		return 1
	for rid in ["parts", "power", "water", "ore", "special_material"]:
		_ok(config.resources.has(StringName(rid)), "资源已定义: %s" % rid)
	_ok(config.levels.has(&"level_1"), "关卡 level_1 已加载")
	_ok(config.blueprints.size() >= 5, "工厂蓝图 ≥5（零代码扩展的配置基础）")
	_test_config_validation()

	print("== T1: 实体创建 / 销毁 ==")
	var w1 := _make_world(config)
	var id1 := w1.create_entity()
	_ok(w1.is_alive(id1), "create_entity 后实体存活")
	var hp := Health.new()
	hp.max_hp = 10.0
	hp.hp = 10.0
	w1.add_component(id1, hp)
	_ok(w1.has_component(id1, &"Health"), "add_component 后可查询")
	_ok(w1.get_component(id1, &"Health") == hp, "get_component 返回同一实例")
	_ok((w1.mask_of(id1) & Entity.bit_for(&"Health")) != 0, "组件位标记已置位")
	var queried := w1.query(&"Health")
	_ok(queried.has(id1), "类型索引 query() 命中")
	w1.destroy_entity(id1)
	_ok(not w1.is_alive(id1), "destroy_entity 后立即不算存活（延迟到帧末清理）")
	_ok(w1.has_component(id1, &"Health"), "帧末清理前组件仍在")
	var destroyed_ids: Array = []
	w1.entity_destroyed.connect(func(eid): destroyed_ids.append(eid))
	w1.tick(DT)
	_ok(not w1.has_component(id1, &"Health"), "帧末 cleanup 移除全部组件")
	_ok(destroyed_ids.has(id1), "entity_destroyed 信号已发出")

	print("== T2: 敌人沿路径推进并计圈 ==")
	var w2 := _make_world(config)
	var eid2 := _spawn_test_enemy(w2, config, &"slime")
	var pf = w2.get_component(eid2, &"PathFollower")
	var en2 = w2.get_component(eid2, &"Enemy")
	var start_dist: float = pf.distance
	var pos0: Vector2 = w2.path.point_at(pf.distance)
	for i in 10:
		w2.tick(DT)
	_ok(pf.distance > start_dist + 50.0, "10 tick 后 distance 推进 (%.1f → %.1f)" % [start_dist, pf.distance])
	_ok(w2.path.point_at(pf.distance).distance_to(pos0) > 1.0, "路径世界坐标随推进改变")
	var ticks2 := 0
	while en2.laps_done < 1 and ticks2 < 1000:
		w2.tick(DT)
		ticks2 += 1
	_ok(en2.laps_done >= 1, "敌人走完一圈 laps_done ≥ 1（用时 %d tick）" % ticks2)
	_ok(ticks2 < 1000, "计圈在预算内完成")

	print("== T2b: 减速地块生效 ==")
	var w2b := _make_world(config)
	var eid2b := w2b.create_entity() # 纯 PathFollower，无波次归属
	var pf2b := PathFollower.new()
	pf2b.path_id = config.get_level(&"level_1")["path_id"]
	pf2b.speed = 100.0
	pf2b.distance = 160.0 # 单元格 [4,1]（slow，speed_mult 0.5）起点弧长
	w2b.add_component(eid2b, pf2b)
	for i in 10:
		w2b.tick(DT)
	# 满速应到 260；减速带内 1 秒只走 50 → 约 210
	_ok(pf2b.distance < 240.0 and pf2b.distance > 195.0,
		"减速带使推进变慢（1 秒后 distance=%.1f，满速应为 260）" % pf2b.distance)

	print("== T3: 波次完成判定 → 撑过 N 波胜利 ==")
	var w3 := _make_world(config)
	var wave_events: Array = []
	var won_events: Array = []
	w3.wave_completed.connect(func(w): wave_events.append(w))
	w3.game_won.connect(func(): won_events.append(true))
	var ticks3 := 0
	while w3.state.is_playing() and ticks3 < 1500:
		w3.tick(DT)
		ticks3 += 1
	_ok(wave_events.size() >= 1, "至少完成 1 波（wave_completed 次数=%d）" % wave_events.size())
	_ok(w3.state.waves_survived == wave_events.size(), "waves_survived 与信号一致（%d）" % w3.state.waves_survived)
	_ok(w3.state.status == GameState.STATUS_WON, "3 波全部走完判胜（status=%s，用时 %d tick）" % [w3.state.status, ticks3])
	_ok(won_events.size() == 1, "game_won 信号恰好 1 次")

	print("== T4: 敌人数超上限判败 ==")
	var w4 := _make_world(config)
	var cap := int(config.get_level(&"level_1")["enemy_cap"])
	var lost_events: Array = []
	w4.game_lost.connect(func(): lost_events.append(true))
	for i in cap + 1:
		_spawn_test_enemy(w4, config, &"slime")
	w4.tick(DT)
	_ok(w4.state.status == GameState.STATUS_LOST, "%d 个敌人 > 上限 %d 判败" % [cap + 1, cap])
	_ok(lost_events.size() == 1, "game_lost 信号恰好 1 次")
	_ok(w4.state.enemies_on_path >= cap + 1, "enemies_on_path 统计全部在场敌人（%d = 手动 %d + 波次刷出）" % [w4.state.enemies_on_path, cap + 1])
	var rejects4: Array = []
	w4.command_rejected.connect(func(r): rejects4.append(r))
	w4.push_command({"type": "place_factory", "blueprint_id": "generator", "cell": [3, 3]})
	w4.tick(DT)
	_ok(rejects4.size() == 1, "判败后指令被拒绝")

	print("== T5: 配方产出与欠料停产 ==")
	# T5a 水泵：欠电停产 → 投电产水 → 电尽再停产
	var w5 := _make_world(config)
	var st5 = w5.state
	w5.push_command({"type": "place_factory", "blueprint_id": "pump", "cell": [3, 3]})
	w5.tick(DT)
	var pump_id := _find_factory(w5, &"pump")
	_ok(pump_id != 0, "place_factory 指令创建工厂实体")
	_ok(w5.grid.get_cell(Vector2i(3, 3)).occupant == pump_id, "网格记录占用者")
	var t5 := 0.0
	while t5 < 5.0:
		w5.tick(DT)
		t5 += DT
	var prod5 = w5.get_component(pump_id, &"Production")
	_ok(st5.get_amount(&"water") == 0, "欠料（无电力）时零产出")
	_ok(not prod5.active and prod5.progress == 0.0, "停产待料：active=false, progress=0")
	st5.add(&"power", 3)
	var guard5 := 0
	while st5.get_amount(&"power") > 0 and guard5 < 600:
		w5.tick(DT)
		guard5 += 1
	var t5b := 0.0
	while t5b < 3.0: # 等缓冲汇入
		w5.tick(DT)
		t5b += DT
	_ok(st5.get_amount(&"water") == 3, "投入 3 电力产出 3 水（实际 %d）" % st5.get_amount(&"water"))
	_ok(st5.get_amount(&"power") == 0, "电力作为配方输入被逐次扣除")
	var water_at_stop: int = st5.get_amount(&"water")
	var t5c := 0.0
	while t5c < 5.0:
		w5.tick(DT)
		t5c += DT
	_ok(st5.get_amount(&"water") == water_at_stop, "电力耗尽后停产（水停在 %d）" % water_at_stop)
	_ok(not prod5.active, "欠料时 active=false")
	# T5b 发电机：无输入配方持续产电（电力是普通资源 §7）
	var w5b := _make_world(config)
	w5b.push_command({"type": "place_factory", "blueprint_id": "generator", "cell": [3, 3]})
	w5b.tick(DT)
	var gen_id := _find_factory(w5b, &"generator")
	_ok(gen_id != 0, "发电机放置成功")
	var t5d := 0.0
	while t5d < 6.0:
		w5b.tick(DT)
		t5d += DT
	_ok(w5b.state.get_amount(&"power") >= 2, "发电机产出电力（当前 %d）" % w5b.state.get_amount(&"power"))

	print("== T6: 索敌 → 射弹 → 击杀入账 ==")
	var w6 := _make_world(config)
	var st6 = w6.state
	st6.add(&"parts", 50)
	w6.push_command({"type": "place_factory", "blueprint_id": "gun_turret", "cell": [4, 2]})
	w6.tick(DT)
	var turret_id := _find_factory(w6, &"gun_turret")
	_ok(turret_id != 0, "炮塔放置成功")
	_ok(st6.get_amount(&"parts") == 40, "蓝图 cost 扣费 10 零件（余额 %d）" % st6.get_amount(&"parts"))
	var eid6 := _spawn_test_enemy(w6, config, &"slime")
	var died6: Array = []
	w6.entity_died.connect(func(e): died6.append(e))
	var ticks6 := 0
	while w6.is_alive(eid6) and ticks6 < 1200:
		w6.tick(DT)
		ticks6 += 1
	_ok(not w6.is_alive(eid6), "炮塔击杀目标敌人（用时 %d tick）" % ticks6)
	_ok(died6.has(eid6), "entity_died 信号发出")
	_ok(st6.get_amount(&"parts") > 40, "击杀掉落入账零件（余额 %d）" % st6.get_amount(&"parts"))

	print("== T7: 光环 BUFF/DEBUFF ==")
	var w7 := _make_world(config)
	var st7 = w7.state
	st7.add(&"parts", 20)
	st7.add(&"special_material", 5)
	w7.push_command({"type": "place_factory", "blueprint_id": "frost_beacon", "cell": [4, 2]})
	w7.push_command({"type": "place_factory", "blueprint_id": "command_post", "cell": [3, 3]})
	w7.tick(DT)
	var beacon_id := _find_factory(w7, &"frost_beacon")
	var post_id := _find_factory(w7, &"command_post")
	_ok(beacon_id != 0 and post_id != 0, "霜冻信标与指挥所放置成功")
	_ok(st7.get_amount(&"parts") == 15 and st7.get_amount(&"special_material") == 3,
		"两种蓝图 cost 均正确扣费（parts=%d, special=%d）" % [st7.get_amount(&"parts"), st7.get_amount(&"special_material")])
	var eid7 := _spawn_test_enemy(w7, config, &"slime")
	var t7 := 0.0
	while t7 < 1.6:
		w7.tick(DT)
		t7 += DT
	var eff7 = w7.get_component(eid7, &"Effect")
	_ok(eff7 != null and eff7.has_stat(GameConfig.STAT_MOVE_SPEED_MULT),
		"路径敌人被施加 DEBUFF（霜冻信标）")
	if eff7 != null:
		_ok(is_equal_approx(eff7.get_value(GameConfig.STAT_MOVE_SPEED_MULT), 0.5),
			"DEBUFF 数值来自配置 0.5")
	var eff_t7 = w7.get_component(beacon_id, &"Effect")
	_ok(eff_t7 == null or not eff_t7.has_stat(GameConfig.STAT_MOVE_SPEED_MULT),
		"信标自身不被自己的敌方 DEBUFF 作用")
	var neighbor_id := _nearest_factory(w7, post_id)
	var neighbor_eff = w7.get_component(neighbor_id, &"Effect")
	_ok(neighbor_eff != null and neighbor_eff.has_stat(GameConfig.STAT_ATTACK_DAMAGE_MULT),
		"邻近工厂被施加 BUFF（指挥所 damage_up）")
	var e := Effect.new()
	e.apply(&"smoke_stat", 1.5, 0.3)
	_ok(e.has_stat(&"smoke_stat"), "Effect 施加条目")
	e.tick_down(0.5)
	_ok(not e.has_stat(&"smoke_stat"), "Effect 过期回收")

	print("== T8: 打出卡牌自动补抽 ==")
	var w8 := _make_world(config)
	var cs8 = w8.get_system("CardSystem")
	var h0: int = cs8.deck.hand.size()
	_ok(h0 == int(config.get_level(&"level_1")["hand_start"]), "初始手牌 = hand_start（%d 张）" % h0)
	w8.state.add(&"parts", 100)
	w8.push_command({"type": "play_card", "card_index": 0, "cell": [3, 2]})
	w8.tick(DT)
	_ok(cs8.deck.hand.size() == h0, "打出 1 张后自动补 1 张，手牌数不变（%d）" % cs8.deck.hand.size())
	_ok(cs8.deck.pending_draw == 0, "补抽已执行（pending_draw=0）")
	var cell8 = w8.grid.get_cell(Vector2i(3, 2))
	_ok(cell8.occupant != 0 or cell8.tile_type != &"", "卡牌效果落地（格子被占用或写入地块）")
	var rejects8: Array = []
	w8.command_rejected.connect(func(r): rejects8.append(r))
	w8.push_command({"type": "play_card", "card_index": 99, "cell": [3, 2]})
	w8.tick(DT)
	_ok(rejects8.size() == 1, "非法手牌下标被拒绝")
	_ok(cs8.deck.hand.size() == h0, "拒绝指令不扣手牌")
	# 路径格不可建工厂：从手牌挑一张工厂卡打出（减速卡放路径格是合法的，故不随机取下标）
	var factory_idx := -1
	for i in cs8.deck.hand.size():
		var cid = cs8.deck.hand[i]
		if str(config.get_card(cid)["effect"]["type"]) == "place_factory":
			factory_idx = i
			break
	_ok(factory_idx >= 0, "手牌中存在工厂卡")
	if factory_idx >= 0:
		w8.push_command({"type": "play_card", "card_index": factory_idx, "cell": [1, 1]})
		w8.tick(DT)
		_ok(rejects8.size() == 2, "路径格放置工厂被拒绝")
		_ok(cs8.deck.hand.size() == h0, "放置失败回滚卡费与手牌（仍 %d 张）" % cs8.deck.hand.size())

	print("======== 结果: %d/%d 通过，%d 失败 ========" % [_checks - _failures, _checks, _failures])
	return _failures


## 负向校验：缺字段必须报错、加载失败（§9「缺字段直接报错而非静默默认」）。
func _test_config_validation() -> void:
	print("== T9: 配置缺字段必须报错（预期的错误输出见下）==")
	var dir := "user://smoke_bad_data/"
	var d := DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive("smoke_bad_data")
	var names := [
		"resources.json", "enemies.json", "recipes.json", "factories.json",
		"buffs.json", "cards.json", "levels.json",
	]
	for n in names:
		var text := FileAccess.get_file_as_string("res://data/" + n)
		var f := FileAccess.open(dir + n, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	# 故意写坏 resources.json：资源缺 name 字段
	var bf := FileAccess.open(dir + "resources.json", FileAccess.WRITE)
	if bf != null:
		bf.store_string('{"resources": [{"id": "stone"}]}')
		bf.close()
	var bad := GameConfig.new()
	var ok := bad.load_from(dir)
	_ok(not ok, "缺 name 字段的配置加载失败（未静默通过）")
	var found := false
	for e in bad.get_errors():
		if str(e).find("缺字段 'name'") != -1:
			found = true
		print("    预期错误: " + str(e))
	_ok(found, "错误信息包含“缺字段 'name'”")


# ================================================================ 构建辅助

## 按 §5 固定顺序组装 11 个系统的世界（bootstrap 已提取到 scripts/bootstrap.gd）。
## 用 preload 而非 class_name：headless -s 不重扫类缓存，避免 Bootstrap 未注册。
const BootstrapScript = preload("res://scripts/bootstrap.gd")


func _make_world(config) -> World:
	return BootstrapScript.build_world(config, &"level_1")


func _spawn_test_enemy(world, config, enemy_id: StringName) -> int:
	var def: Dictionary = config.get_enemy(enemy_id)
	var id: int = world.create_entity()
	var pf := PathFollower.new()
	pf.path_id = config.get_level(world.state.level_id)["path_id"]
	pf.distance = 0.0
	pf.speed = float(def["speed"])
	world.add_component(id, pf)
	var hp := Health.new()
	hp.max_hp = float(def["hp"])
	hp.hp = float(def["hp"])
	world.add_component(id, hp)
	var en := Enemy.new()
	en.wave_id = -1
	en.elite = bool(def["elite"])
	en.loot_id = def["loot_id"]
	en.loot_amount = int(def["loot_amount"])
	world.add_component(id, en)
	return id


func _find_factory(world, blueprint_id: StringName) -> int:
	for id in world.query(&"Factory"):
		var f = world.get_component(id, &"Factory")
		if f.blueprint_id == blueprint_id:
			return id
	return 0


## 距 source 最近的其他工厂实体（指挥所光环测试用）。
func _nearest_factory(world, source_id: int) -> int:
	var origin = EntityLocator.position(world, source_id)
	var best := 0
	var best_d := 1000000.0
	for id in world.query(&"Factory"):
		if id == source_id:
			continue
		var pos = EntityLocator.position(world, id)
		if pos == null:
			continue
		var dist: float = origin.distance_to(pos)
		if dist < best_d:
			best_d = dist
			best = id
	return best
