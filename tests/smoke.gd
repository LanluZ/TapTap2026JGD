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
	for eid in ["slime", "golem", "bat", "swarm", "moth", "slime_king"]:
		_ok(config.enemies.has(StringName(eid)), "敌人已定义: %s" % eid)
	_ok(bool(config.get_enemy(&"moth")["flying"]), "moth 标记为飞行怪")
	_ok(not bool(config.get_enemy(&"slime")["flying"]), "非飞行怪 flying 缺省 false")
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

	print("== T2c: 飞行怪无视减速地块 ==")
	var w2c := _make_world(config)
	var eid2c := w2c.create_entity()
	var pf2c := PathFollower.new()
	pf2c.path_id = config.get_level(&"level_1")["path_id"]
	pf2c.speed = 120.0
	pf2c.distance = 160.0 # 同 T2b，起点在减速格 [4,1]
	w2c.add_component(eid2c, pf2c)
	var en2c := Enemy.new()
	en2c.flying = true
	w2c.add_component(eid2c, en2c)
	for i in 10:
		w2c.tick(DT)
	_ok(pf2c.distance > 270.0,
		"飞行怪在减速带上保持满速（distance=%.1f，满速应约 280）" % pf2c.distance)

	print("== T3: 波次完成判定 → 撑过 N 波胜利（清场后才判胜） ==")
	var w3 := _make_world(config)
	# 本测只验证「达标后不清场不判胜」的语义，与关卡实际波数（levels.json 可调，当前 50）解耦
	# 失败线同理解耦：本测不击杀，前 3 波累积数会随关卡难度曲线变化，不能拿真实 cap 判负
	w3.state.enemy_cap = 999
	w3.get_system("WaveSystem").objective = WaveSystem.SurviveWavesObjective.new(3)
	var wave_events: Array = []
	var won_events: Array = []
	w3.wave_completed.connect(func(w): wave_events.append(w))
	w3.game_won.connect(func(): won_events.append(true))
	var ticks3 := 0
	# 产品裁定：撑过目标波数不立刻判胜，等场上敌人清空才判胜（wave_system.objective_met）
	while w3.state.waves_survived < 3 and ticks3 < 1500:
		w3.tick(DT)
		ticks3 += 1
	_ok(wave_events.size() >= 1, "至少完成 1 波（wave_completed 次数=%d）" % wave_events.size())
	_ok(w3.state.waves_survived == wave_events.size(), "waves_survived 与信号一致（%d）" % w3.state.waves_survived)
	var alive3 := 0
	for eid in w3.query(&"Enemy"):
		if w3.is_alive(eid):
			alive3 += 1
	_ok(w3.state.is_playing() and alive3 > 0,
		"3 波走完但场上还有敌人 → 仍 playing（status=%s，敌 %d，用时 %d tick）" % [w3.state.status, alive3, ticks3])
	for eid in w3.query(&"Enemy").keys():
		if w3.is_alive(eid):
			w3.destroy_entity(eid)
	w3.tick(DT)
	_ok(w3.state.status == GameState.STATUS_WON and won_events.size() == 1,
		"清空场上敌人 → 判胜且 game_won 恰好 1 次（status=%s，信号 %d）" % [w3.state.status, won_events.size()])

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
	# T5a 水泵：欠电停产 → 投电产水进本地缓冲（任务 5：水不进资源池）→ 电尽再停产
	var w5 := _make_world(config)
	var st5 = w5.state
	var lg5 = w5.get_system("LogisticsSystem")
	w5.push_command({"type": "place_factory", "blueprint_id": "pump", "cell": [3, 3]})
	w5.tick(DT)
	var pump_id := _find_factory(w5, &"pump")
	_ok(pump_id != 0, "place_factory 指令创建工厂实体")
	_ok(w5.grid.get_cell(Vector2i(3, 3)).occupant == pump_id, "网格记录占用者")
	_ok(lg5 != null, "LogisticsSystem 已注册（本地缓冲查询入口）")
	var t5 := 0.0
	while t5 < 5.0:
		w5.tick(DT)
		t5 += DT
	var prod5 = w5.get_component(pump_id, &"Production")
	_ok(lg5.buffer_of(pump_id) == 0 and st5.get_amount(&"water") == 0, "欠料（无电力）时零产出")
	_ok(not prod5.active and prod5.progress == 0.0, "停产待料：active=false, progress=0")
	st5.add(&"power", 3)
	var guard5 := 0
	while st5.get_amount(&"power") > 0 and guard5 < 600:
		w5.tick(DT)
		guard5 += 1
	var t5b := 0.0
	while t5b < 3.0: # 等已扣电的周期走完
		w5.tick(DT)
		t5b += DT
	_ok(lg5.buffer_of(pump_id) == 3, "投入 3 电力产 3 水进本地缓冲（实际 %d）" % lg5.buffer_of(pump_id))
	_ok(st5.get_amount(&"water") == 0, "水不再汇入资源池（water=%d）" % st5.get_amount(&"water"))
	_ok(st5.get_amount(&"power") == 0, "电力作为配方输入被逐次扣除")
	var water_at_stop: int = lg5.buffer_of(pump_id)
	var t5c := 0.0
	while t5c < 5.0:
		w5.tick(DT)
		t5c += DT
	_ok(lg5.buffer_of(pump_id) == water_at_stop, "电力耗尽后停产（本地缓冲停在 %d）" % water_at_stop)
	_ok(st5.get_amount(&"water") == 0, "停产期间水仍不进池（water=%d）" % st5.get_amount(&"water"))
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
	w6.state.waves_running = false # 关掉波次刷怪以免多目标分流把「单目标击杀链路」拖成边际失败
	# （同 T6b 做法）。裁定 T6-9 起炮塔落地即带弹（蓝图 start_ammo），首发即全伤。
	var st6 = w6.state
	st6.add(&"parts", 50)
	w6.push_command({"type": "place_factory", "blueprint_id": "gun_turret", "cell": [4, 2]})
	w6.tick(DT)
	var turret_id := _find_factory(w6, &"gun_turret")
	_ok(turret_id != 0, "炮塔放置成功")
	_ok(st6.get_amount(&"parts") == 36, "蓝图 cost 扣费 14 零件（含喜水×4，余额 %d）" % st6.get_amount(&"parts"))
	# 裁定 T6-9：轻炮塔蓝图 start_ammo=6 → 放置即满仓，不再需要手工投料装弹
	# （投料/拒收路径由 ammo_hydro_test T6 覆盖）。本用例只测「索敌→射弹→击杀入账」链路。
	_ok(int(w6.get_component(turret_id, &"Attack").ammo) == 6,
		"轻炮塔落地即满仓 ammo=6（蓝图 start_ammo）")
	var eid6 := _spawn_test_enemy(w6, config, &"slime")
	var died6: Array = []
	w6.entity_died.connect(func(e): died6.append(e))
	# T6-1：「敌人死了」对「有弹全伤」零判别力——断弹半伤（×0.5）同样能打死史莱姆。
	# 单独锁定首发的定格伤害 == base（弹药 > 0 ⇒ 不乘 DRY_DAMAGE_MULT）。
	var atk6 = w6.get_component(turret_id, &"Attack")
	var base_dmg6: float = atk6.damage
	w6.get_component(eid6, &"PathFollower").distance = 100.0 # 进场即入射程，首发确定发生
	atk6.cooldown_left = 0.0
	w6.tick(DT)
	var ticks6 := 1
	var first_dmg6 := -1.0
	for pid in w6.query(&"Projectile"):
		if not w6.is_alive(pid):
			continue
		first_dmg6 = float(w6.get_component(pid, &"Projectile").damage)
	_ok(is_equal_approx(first_dmg6, base_dmg6),
		"首发生效伤害 == base（%.1f vs %.1f）——有弹全伤，非断弹半伤" % [first_dmg6, base_dmg6])
	_ok(int(atk6.ammo) == 5, "全伤发每发扣 1 矿（6 → %d）" % int(atk6.ammo))
	while w6.is_alive(eid6) and ticks6 < 1200:
		w6.tick(DT)
		ticks6 += 1
	_ok(not w6.is_alive(eid6), "炮塔击杀目标敌人（用时 %d tick）" % ticks6)
	_ok(died6.has(eid6), "entity_died 信号发出")
	_ok(st6.get_amount(&"parts") > 36, "击杀掉落入账零件（余额 %d）" % st6.get_amount(&"parts"))

	print("== T6b: 瞄准策略（DNA 瞄准座）==")
	# 纯函数：座8 改 farthest → Attack.targeting 跟着变
	var g_tgt: Array = config.blueprints[&"gun_turret"]["genome"].duplicate(true)
	g_tgt[8] = { "bases": "T" } # farthest 的碱基（基因型即数据）
	var tgt_specs: Array = Genome.express(g_tgt, config.genes, "gun_turret", "轻炮")
	var tgt_value := ""
	for s in tgt_specs:
		if s.get("type", "") == "Attack":
			tgt_value = String(s["targeting"])
	_ok(tgt_value == "farthest", "瞄准座改为 farthest → Attack.targeting 表达为 farthest")
	var w6b := _make_world(config)
	w6b.state.waves_running = false # 关掉波次刷怪，避免干扰索敌
	w6b.state.add(&"parts", 50)
	w6b.push_command({"type": "place_factory", "blueprint_id": "gun_turret", "cell": [4, 2]})
	w6b.tick(DT)
	var tid6b := _find_factory(w6b, &"gun_turret")
	var atk6b = w6b.get_component(tid6b, &"Attack")
	_ok(String(atk6b.targeting) == "nearest", "蓝图默认瞄准策略来自 DNA（nearest）")
	var near_low := _spawn_test_enemy(w6b, config, &"slime") # 30hp，更近
	var far_high := _spawn_test_enemy(w6b, config, &"golem") # 240hp，更远
	w6b.get_component(near_low, &"PathFollower").distance = 100.0
	w6b.get_component(far_high, &"PathFollower").distance = 300.0
	atk6b.targeting = &"highest_hp"
	atk6b.cooldown_left = 0.0
	w6b.tick(DT)
	var shot_target := -1
	for pid in w6b.query(&"Projectile"):
		if not w6b.is_alive(pid):
			continue
		shot_target = w6b.get_component(pid, &"Projectile").target
	_ok(shot_target == far_high, "highest_hp 越过更近目标，选中血量更高的敌人")
	atk6b.targeting = &"lowest_hp"
	atk6b.cooldown_left = 0.0
	for pid in w6b.query(&"Projectile"):
		w6b.destroy_entity(pid)
	w6b.tick(DT)
	shot_target = -1
	for pid in w6b.query(&"Projectile"):
		if not w6b.is_alive(pid):
			continue
		shot_target = w6b.get_component(pid, &"Projectile").target
	_ok(shot_target == near_low, "lowest_hp 选中血量更低的目标")

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

	# start_ammo（裁定 T6-9）写在无 Attack 的蓝图上 = 静默无效配置 → 必须报错
	# 这份坏配置要能走到蓝图校验：补上 T9 文件清单里没拷的 genes.json（基因组校验依据）
	var genes_text := FileAccess.get_file_as_string("res://data/genes.json")
	var gf0 := FileAccess.open(dir + "genes.json", FileAccess.WRITE)
	if gf0 != null:
		gf0.store_string(genes_text)
		gf0.close()
	var res_text := FileAccess.get_file_as_string("res://data/resources.json")
	var rf := FileAccess.open(dir + "resources.json", FileAccess.WRITE)
	if rf != null:
		rf.store_string(res_text)
		rf.close()
	var fac = JSON.parse_string(FileAccess.get_file_as_string("res://data/factories.json"))
	for b in (fac as Dictionary)["blueprints"]:
		if str((b as Dictionary)["id"]) == "generator":
			(b as Dictionary)["start_ammo"] = 1
	var ff := FileAccess.open(dir + "factories.json", FileAccess.WRITE)
	if ff != null:
		ff.store_string(JSON.stringify(fac))
		ff.close()
	var bad2 := GameConfig.new()
	var ok2 := bad2.load_from(dir)
	var found2 := false
	for e in bad2.get_errors():
		if str(e).find("start_ammo") != -1:
			found2 = true
			print("    预期错误: " + str(e))
	_ok(not ok2 and found2, "start_ammo 写在无 Attack 的蓝图上 → 加载失败（不静默忽略）")


# ================================================================ 构建辅助

## 按 §5 固定顺序组装 12 个系统的世界（命令 → 物流 #1.5 → 波次 … → 清理；bootstrap 已提取到 scripts/bootstrap.gd）。
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
	en.flying = bool(def.get("flying", false))
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
