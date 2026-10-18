extends SceneTree
## 生产端物理化 headless 验证（任务 5/8）：
##   ① recipes.json 三条配方精确取值（synth_special 无 ore 输入）；
##   ② 水泵/矿机产出进本地物流缓冲（容量 4），无路可走时缓冲满 → 停产（扣款前判据）；
##   ③ 接管/接带后排水/排矿 → 恢复开工；
##   ④ 装配台靠传送带进料（deliver_ore）：库存 ≥3 才开产，开产扣 3 矿 + 池电 2，库存上限 6；
##   ⑤ 水/矿不再进 state 资源池（state.get_amount 恒 0）。
## 运行：godot --headless --path <项目目录> -s res://tests/production_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const DT := 0.1

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false
var _config = null


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


func _new_world():
	if _config == null:
		_config = GameConfig.load_all()
	return BootstrapScript.build_world(_config, &"level_1")


func _logi(world):
	return world.get_system("LogisticsSystem")


## 开局资源补给（放置 blueprint 用）。水/矿已不是池资源（任务 5），故只补池内资源。
func _grant(world) -> void:
	for rid in ["parts", "power", "special_material"]:
		world.state.add(StringName(rid), 200)


func _place_factory_at(world, blueprint: String, cell: Vector2i) -> int:
	world.push_command({"type": "place_factory", "blueprint_id": blueprint, "cell": [cell.x, cell.y]})
	world.tick(DT)
	var c = world.grid.get_cell(cell)
	if c == null:
		return 0
	return int(c.occupant)


func _place(world, kind: String, cells: Array, dir_v: Array) -> void:
	world.push_command({"type": "place_line", "kind": kind, "cells": cells, "dir": dir_v})
	world.tick(DT)


## 按蓝图建实体但**不 tick**：绕过 CommandSystem/ProductionSystem，
## 模拟「刚放置、还没跑过任何 Production tick」的实体（放置当帧 Logistics 先于
## Production 执行、存档恢复、工具直接构造实体等路径）。
func _spawn_without_tick(world, blueprint: String, cell: Vector2i) -> int:
	var bp: Dictionary = world.config.get_blueprint(StringName(blueprint))
	if bp.is_empty():
		return 0
	var id: int = world.create_entity()
	var specs: Array = Genome.express(bp["genome"], world.config.genes, blueprint, blueprint)
	for sd in specs:
		var comp = GameConfig.make_component(str(sd.get("type", "")), sd)
		if comp == null:
			return 0
		if comp is GridPosition:
			comp.cell = cell
		world.add_component(id, comp)
	return id


func _ticks(world, n: int) -> void:
	for i in n:
		world.tick(DT)


func _items(world, cell: Vector2i) -> Array:
	var out: Array = []
	var c = world.grid.get_cell(cell)
	if c == null:
		return out
	for v in c.belt_items:
		out.append(float(v))
	return out


func _set_items(world, cell: Vector2i, arr: Array) -> void:
	var c = world.grid.get_cell(cell)
	c.belt_items.clear()
	for v in arr:
		c.belt_items.append(float(v))


## 本地库存当前值（装配台矿堆走 ResourceBuffer.stored）。
func _stock(world, id: int, rid: StringName) -> int:
	var buf = world.get_component(id, &"ResourceBuffer")
	if buf == null:
		return -1
	return buf.count_of(rid)


func _run() -> int:
	print("======== 生产端物理化（任务 5）========")
	_config = GameConfig.load_all()
	_ok(_config != null, "GameConfig.load_all() 成功")
	if _config == null:
		return 1

	_t1_recipes()
	_t2_pump_stall()
	_t3_miner_stall()
	_t4_assembler_stock()
	_t5_no_pool()
	_t6_deliver_routing()
	_t7_no_tick_deliver()

	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	return _failures


# ================================================================ T1 配方取值

func _t1_recipes() -> void:
	print("== T1: recipes.json 三条配方精确取值 ==")
	var pump: Dictionary = _config.get_recipe(&"pump_water")
	var mine: Dictionary = _config.get_recipe(&"mine_ore")
	var synth: Dictionary = _config.get_recipe(&"synth_special")
	_ok(pump["inputs"] == {&"power": 1} and pump["outputs"] == {&"water": 1},
		"pump_water {power:1}→{water:1}（实际 %s → %s）" % [str(pump["inputs"]), str(pump["outputs"])])
	_ok(mine["inputs"] == {&"power": 1} and mine["outputs"] == {&"ore": 2},
		"mine_ore {power:1}→{ore:2}（实际 %s → %s）" % [str(mine["inputs"]), str(mine["outputs"])])
	_ok(synth["inputs"] == {&"power": 2} and synth["outputs"] == {&"special_material": 1},
		"synth_special {power:2}→{special_material:1}（实际 %s → %s）" % [str(synth["inputs"]), str(synth["outputs"])])
	_ok(not (synth["inputs"] as Dictionary).has(&"ore"), "synth_special 无 ore 输入（矿改传送带进料）")


# ================================================================ T2 水泵缓冲满停产 / 接管恢复

func _t2_pump_stall() -> void:
	print("== T2: 无管水泵缓冲积满 4 → 停产；接管后恢复 ==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	_ok(pump != 0 and lg != null, "水泵落位 [4,3]（实体 %d）" % pump)
	var prod = w.get_component(pump, &"Production")
	var buf = w.get_component(pump, &"ResourceBuffer")
	_ok(prod != null and buf != null, "水泵带 Production + ResourceBuffer")
	w.state.resources[&"power"] = 20
	_ticks(w, 60) # 6.0 秒 = 6 个周期
	_ok(lg.buffer_of(pump) == 4, "无对接管 6 秒后本地缓冲积满 4（实际 %d）" % lg.buffer_of(pump))
	_ok(lg.buffer_full(pump), "buffer_full 判据为真（停产依据）")
	_ok(not prod.active and prod.progress == 0.0, "缓冲满：active=false, progress=0")
	var power_at_stall: int = w.state.get_amount(&"power")
	_ok(power_at_stall < 20 and power_at_stall > 0, "停产前已扣电开工（20→%d）" % power_at_stall)
	_ticks(w, 30) # 3.0 秒
	_ok(w.state.get_amount(&"power") == power_at_stall,
		"缓冲满后不再扣电（电力停在 %d）" % w.state.get_amount(&"power"))
	_ok(lg.buffer_of(pump) == 4, "缓冲满后不再产出（仍 %d，不溢出）" % lg.buffer_of(pump))
	_ok(w.state.get_amount(&"water") == 0, "水不进资源池（water=%d）" % w.state.get_amount(&"water"))

	# 接管：排水 1 水/秒 → 腾出空间 → 恢复开工
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_ok(lg.pump_connected(pump), "接管后泵判定为有对接管")
	var min_buf := 99
	for i in 30: # 3.0 秒
		w.tick(DT)
		min_buf = mini(min_buf, lg.buffer_of(pump))
	_ok(min_buf <= 3, "排水后缓冲降到 ≤3（实际最低 %d）" % min_buf)
	_ok(w.state.get_amount(&"power") < power_at_stall,
		"腾出空间后恢复开工（电力 %d→%d）" % [power_at_stall, w.state.get_amount(&"power")])
	_ok(lg.buffer_of(pump) <= 4, "恢复后缓冲仍不超过 4（实际 %d）" % lg.buffer_of(pump))
	_ok(w.state.get_amount(&"water") == 0, "排水/生产全程水不进资源池（water=%d）" % w.state.get_amount(&"water"))


# ================================================================ T3 矿机同构

func _t3_miner_stall() -> void:
	print("== T3: 矿机同构（无带积满停产 / 接带恢复 + 注入 ≤2 块/秒）==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var miner: int = _place_factory_at(w, "miner", Vector2i(4, 3))
	var prod = w.get_component(miner, &"Production")
	_ok(miner != 0 and prod != null, "矿机落位 [4,3]（实体 %d）" % miner)
	w.state.resources[&"power"] = 20
	_ticks(w, 50) # 5.0 秒：两次周期后缓冲 2+2=4
	_ok(lg.buffer_of(miner) == 4, "无出料带 5 秒后缓冲积满 4（实际 %d）" % lg.buffer_of(miner))
	_ok(not prod.active, "缓冲满：active=false")
	var power_at_stall: int = w.state.get_amount(&"power")
	_ticks(w, 30)
	_ok(w.state.get_amount(&"power") == power_at_stall,
		"缓冲满后不再扣电（电力停在 %d）" % w.state.get_amount(&"power"))
	_ok(w.state.get_amount(&"ore") == 0, "矿不进资源池（ore=%d）" % w.state.get_amount(&"ore"))

	# 接出料带（背向矿机）：注入 → 缓冲下降 → 生产恢复
	_place(w, "belt", [[4, 2]], [0, -1])
	var min_buf := 99
	var seen_items := false
	for i in 40: # 4.0 秒
		w.tick(DT)
		min_buf = mini(min_buf, lg.buffer_of(miner))
		if not _items(w, Vector2i(4, 2)).is_empty():
			seen_items = true
	_ok(min_buf <= 3, "带排矿后缓冲降到 ≤3（实际最低 %d）" % min_buf)
	_ok(seen_items, "矿块出现在出料带上")
	_ok(w.state.get_amount(&"power") < power_at_stall,
		"有出料口后恢复开工（电力 %d→%d）" % [power_at_stall, w.state.get_amount(&"power")])
	_ok(w.state.get_amount(&"ore") == 0, "注入/生产全程矿不进资源池（ore=%d）" % w.state.get_amount(&"ore"))


# ================================================================ T4 装配台进料

func _t4_assembler_stock() -> void:
	print("== T4: 装配台传送带进料（≥3 开产、扣 3 矿 + 电 2、库存上限 6）==")
	var w = _new_world()
	_grant(w)
	var asm: int = _place_factory_at(w, "assembler", Vector2i(4, 3))
	_ok(asm != 0, "装配台落位 [4,3]（实体 %d）" % asm)
	var prod = w.get_component(asm, &"Production")
	var buf = w.get_component(asm, &"ResourceBuffer")
	_ok(prod != null and buf != null, "装配台带 Production + ResourceBuffer")
	w.state.resources[&"power"] = 20
	var special0: int = w.state.get_amount(&"special_material")
	# (a) 库存 0：有电也不开产
	_ticks(w, 50)
	_ok(_stock(w, asm, &"ore") == 0, "无进料时库存 0（实际 %d）" % _stock(w, asm, &"ore"))
	_ok(w.state.get_amount(&"power") == 20, "库存不足不扣电（power=%d）" % w.state.get_amount(&"power"))
	_ok(not prod.active and prod.progress == 0.0, "库存不足：active=false, progress=0")
	_ok(w.state.get_amount(&"special_material") == special0, "库存不足无产出")
	# (b) 库存 2 仍不开产（< 3）
	_ok(w.deliver_ore(asm) and w.deliver_ore(asm), "deliver_ore 连续入库 2 矿")
	_ok(_stock(w, asm, &"ore") == 2, "库存 2（实际 %d）" % _stock(w, asm, &"ore"))
	_ticks(w, 20)
	_ok(w.state.get_amount(&"power") == 20 and not prod.active, "库存 2 < 3：仍不开产、不扣电")
	# (c) 第 3 矿 → 开产：扣 3 矿 + 电 2，3 秒后产出 1 特殊材料
	_ok(w.deliver_ore(asm), "deliver_ore 入库第 3 矿")
	_ok(_stock(w, asm, &"ore") == 3, "库存 3（实际 %d）" % _stock(w, asm, &"ore"))
	w.tick(DT)
	_ok(prod.active, "库存 ≥3 且电力可扣 → 立即开产（active=true）")
	_ok(_stock(w, asm, &"ore") == 0, "开产扣 3 矿（库存 3→%d）" % _stock(w, asm, &"ore"))
	_ok(w.state.get_amount(&"power") == 18, "开产池扣电 2（20→%d）" % w.state.get_amount(&"power"))
	_ticks(w, 32) # 3.0 秒周期 + 汇入
	_ok(_stock(w, asm, &"special_material") >= 0, "缓冲可查询特殊材料（接口存在）")
	_ticks(w, 15) # 等 flush 1.0 秒
	_ok(w.state.get_amount(&"special_material") == special0 + 1,
		"周期结束产出 1 特殊材料并汇入资源池（实际 %d）" % w.state.get_amount(&"special_material"))
	_ok(w.state.get_amount(&"ore") == 0, "装配台库存矿不进资源池（ore=%d）" % w.state.get_amount(&"ore"))
	# (d) 库存上限 6：第 7 块被拒，块滞留带上（不吞）
	for i in 6:
		w.deliver_ore(asm)
	_ok(_stock(w, asm, &"ore") == 6, "库存上限 6（实际 %d）" % _stock(w, asm, &"ore"))
	_ok(not w.deliver_ore(asm), "库存满 → deliver_ore 返回 false（块留在带上，不丢失）")
	_ok(_stock(w, asm, &"ore") == 6, "拒绝后库存不变（%d）" % _stock(w, asm, &"ore"))


# ================================================================ T5 水/矿恒不进池

func _t5_no_pool() -> void:
	print("== T5: 产出不再进 state 资源池（water/ore 恒 0）==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var miner: int = _place_factory_at(w, "miner", Vector2i(8, 3))
	_ok(pump != 0 and miner != 0, "水泵 + 矿机落位")
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_place(w, "belt", [[8, 2]], [0, -1])
	var water_max := 0
	var ore_max := 0
	var pump_max := 0
	var miner_max := 0
	for i in 100: # 10 秒
		w.tick(DT)
		water_max = maxi(water_max, w.state.get_amount(&"water"))
		ore_max = maxi(ore_max, w.state.get_amount(&"ore"))
		pump_max = maxi(pump_max, lg.buffer_of(pump))
		miner_max = maxi(miner_max, lg.buffer_of(miner))
	_ok(water_max == 0, "10 秒内 state.water 恒 0（最大 %d）" % water_max)
	_ok(ore_max == 0, "10 秒内 state.ore 恒 0（最大 %d）" % ore_max)
	_ok(pump_max > 0 and miner_max > 0, "水/矿改在本地缓冲里周转（峰值 %d 水 / %d 矿）" % [pump_max, miner_max])


# ================================================================ T6 deliver_ore 分流

func _t6_deliver_routing() -> void:
	print("== T6: world.deliver_ore 分流（弹药 / 库存 / 拒收）==")
	var w = _new_world()
	_grant(w)
	var asm: int = _place_factory_at(w, "assembler", Vector2i(4, 3))
	var turret: int = _place_factory_at(w, "gun_turret", Vector2i(6, 3))
	var gen: int = _place_factory_at(w, "generator", Vector2i(8, 3))
	_ok(asm != 0 and turret != 0 and gen != 0, "装配台 / 炮塔 / 发电机落位")
	var deliveries: Array = []
	var rejects: Array = []
	w.ore_delivered.connect(func(e): deliveries.append(int(e)))
	w.ore_rejected.connect(func(e, r): rejects.append([int(e), str(r)]))
	_ok(w.deliver_ore(asm), "装配台（配方带矿堆进料）→ 接收")
	_ok(_stock(w, asm, &"ore") == 1, "接收后库存 +1（%d）" % _stock(w, asm, &"ore"))
	_ok(deliveries.size() == 1 and deliveries[0] == asm, "成功交付发 ore_delivered（%s）" % str(deliveries))
	var turret_atk = w.get_component(turret, &"Attack")
	_ok(w.deliver_ore(turret), "炮塔（有 Attack）：任务 6 起收矿填弹药 → true")
	_ok(int(turret_atk.ammo) == 1, "炮塔弹药 +1（ammo=%d）" % int(turret_atk.ammo))
	_ok(deliveries.size() == 2 and deliveries[1] == turret, "炮塔交付也发 ore_delivered（%s）" % str(deliveries))
	_ok(not w.deliver_ore(gen), "发电机（配方无矿堆进料）→ false（块滞留）")
	_ok(rejects.size() == 1 and int(rejects[0][0]) == gen and str(rejects[0][1]) == "no_feed",
		"发电机拒收发 ore_rejected(gen, no_feed)（%s）" % str(rejects))
	_ok(deliveries.size() == 2, "拒收不发 ore_delivered（%d 次）" % deliveries.size())
	_ok(not w.deliver_ore(9999), "不存在的实体 → false（不报错）")
	# 传送带端头对接装配台：块真正进库存并从带上消失
	var w2 = _new_world()
	_grant(w2)
	var asm2: int = _place_factory_at(w2, "assembler", Vector2i(4, 3))
	_place(w2, "belt", [[4, 2]], [0, 1]) # 端头格 [4,2] dir(0,1) → 指向 [4,3]
	_set_items(w2, Vector2i(4, 2), [1.0])
	w2.tick(DT)
	_ok(_items(w2, Vector2i(4, 2)).is_empty(), "带端头对接装配台：块被收走")
	_ok(_stock(w2, asm2, &"ore") == 1, "块进装配台库存（%d）" % _stock(w2, asm2, &"ore"))


# ================================================================ T7 未跑 Production tick 也进料

func _t7_no_tick_deliver() -> void:
	print("== T7: 刚创建（未跑过任何 Production tick）的装配台立即进料 ==")
	# 回归审查重要#2：上限判据不能依赖 ProductionSystem 每 tick 写回的派生字段 cap。
	var w = _new_world()
	_grant(w)
	var asm: int = _spawn_without_tick(w, "assembler", Vector2i(4, 3))
	_ok(asm != 0, "装配台实体建好（未跑任何 tick，实体 %d）" % asm)
	var buf = w.get_component(asm, &"ResourceBuffer")
	_ok(buf != null and int(buf.cap) == 0,
		"前置条件：未跑 tick 时 cap 还是缺省 0（实际 %d）" % (int(buf.cap) if buf != null else -1))
	_ok(w.deliver_ore(asm), "未跑 Production tick 也接收矿（按 recipe_id 现算上限）")
	_ok(_stock(w, asm, &"ore") == 1, "矿进库存（%d）" % _stock(w, asm, &"ore"))
	_ok(int(buf.cap) == 6, "cap 同步为权威值 6（实际 %d）" % int(buf.cap))
	for i in 5:
		w.deliver_ore(asm)
	_ok(_stock(w, asm, &"ore") == 6, "上限仍为 6（实际 %d）" % _stock(w, asm, &"ore"))
	_ok(not w.deliver_ore(asm), "满 6 后拒收（块滞留，不吞）")
	# 反过来：配方不吃矿的实体（发电机）在同样路径下仍拒收
	var gen: int = _spawn_without_tick(w, "generator", Vector2i(6, 3))
	_ok(gen != 0 and not w.deliver_ore(gen), "未跑 tick 的发电机仍拒收（配方无矿堆进料）")
