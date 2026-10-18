extends SceneTree
## 弹药与水效果消费端 headless 验证（任务 6/8）：
##   ① 嗜水（hydro_thirsty）断水停射，接水当帧恢复；漠水（hydro_none）无感；
##   ② 喜水（hydro_love）有水 → 实际冷却 ×0.8（实测计时，非改字段）；
##   ③ 弹药：上限 6、每发扣 1、断弹 → 冷却 ×2 且伤害 ×0.5（同时）；
##   ④ 断弹惩罚 × 喜水加速**乘算**：base×2×0.8 = 1.28 base；
##   ⑤ deliver_ore 分流：Attack→ammo（满 6 拒收，块滞留端头）/ Production→库存 /
##      其余拒收且发 ore_rejected(entity_id, reason)（**边沿触发**：同因连发只发一次）/
##      DNA 混种矿走弹药（裁定 N4）；
##   ⑥ 生产端：嗜水断水不开工（与欠料同路径）、喜水有水 interval×0.8（实测周期）。
## 运行：godot --headless --path <项目目录> -s res://tests/ammo_hydro_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const AttackScript = preload("res://scripts/components/attack.gd")
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


# ---------------------------------------------------------------- 辅助

func _new_world():
	if _config == null:
		_config = GameConfig.load_all()
	var w = BootstrapScript.build_world(_config, &"level_1")
	w.state.waves_running = false # 关掉波次刷怪，索敌只认测试放的敌人
	return w


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


func _ticks(world, n: int) -> void:
	for i in n:
		world.tick(DT)


## 把某实体的生产周期拉到极大：已 active 的周期永不完成（也不退电），
## 用于隔离「被测实体是否扣电」——泵在放置当帧已 active，改 interval 即冻结其持续扣电。
func _freeze_production(world, id: int) -> void:
	var prod = world.get_component(id, &"Production")
	if prod != null:
		prod.interval = 1.0e9


## 静止测试敌人（speed=0）：distance=300 落在炮塔 [6,2]（世界坐标 416,160）射程内。
func _spawn_enemy(world, enemy_id: StringName = &"slime", dist: float = 300.0) -> int:
	var def: Dictionary = world.config.get_enemy(enemy_id)
	var id: int = world.create_entity()
	var pf := PathFollower.new()
	pf.path_id = world.config.get_level(world.state.level_id)["path_id"]
	pf.distance = dist
	pf.speed = 0.0 # 静止：整段测试内始终在射程内
	world.add_component(id, pf)
	var hp := Health.new()
	hp.max_hp = float(def["hp"])
	hp.hp = float(def["hp"])
	world.add_component(id, hp)
	var en := Enemy.new()
	en.wave_id = -1
	en.elite = bool(def["elite"])
	en.flying = bool(def["flying"])
	en.loot_id = def["loot_id"]
	en.loot_amount = int(def["loot_amount"])
	world.add_component(id, en)
	return id


## 存活射弹数（本 tick 是否发射）。
func _shots(world) -> int:
	var n := 0
	for pid in world.query(&"Projectile").keys():
		if world.is_alive(pid):
			n += 1
	return n


func _clear_projectiles(world) -> void:
	for pid in world.query(&"Projectile").keys():
		if world.is_alive(pid):
			world.destroy_entity(pid)


## 强迫发射一发（冷却清零 + 清场），返回本发伤害/生效冷却/剩余弹药。
func _fire_once(world, atk) -> Dictionary:
	_clear_projectiles(world)
	atk.cooldown_left = 0.0
	world.tick(DT)
	var dmg: float = -1.0
	for pid in world.query(&"Projectile").keys():
		if not world.is_alive(pid):
			continue
		dmg = float(world.get_component(pid, &"Projectile").damage)
	return {"shots": _shots(world), "damage": dmg, "cooldown": float(atk.cooldown_left), "ammo": int(atk.ammo)}


## 实测发射间隔（tick 数）：每 tick 清空射弹（不打断计时），返回相邻两次发射的最小 tick 间隔。
func _min_shot_gap(world, atk, ticks: int) -> int:
	atk.cooldown_left = 0.0
	_clear_projectiles(world)
	var fire_ticks: Array = []
	for i in ticks:
		_clear_projectiles(world)
		world.tick(DT)
		if _shots(world) > 0:
			fire_ticks.append(i)
	if fire_ticks.size() < 2:
		return -1
	var gap: int = 999
	for i in range(1, fire_ticks.size()):
		gap = mini(gap, int(fire_ticks[i]) - int(fire_ticks[i - 1]))
	return gap


## 炮塔测试世界：泵 [4,3]（供水种子）+ 炮塔 [6,2] + 静止敌人；watered 时铺 [5,3][6,3] 供水。
func _turret_world(watered: bool, blueprint: String = "gun_turret") -> Dictionary:
	var w = _new_world()
	_grant(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	if watered:
		_place(w, "pipe", [[5, 3]], [-1, 0])
		_place(w, "pipe", [[6, 3]], [0, -1]) # [6,3] dir(0,-1) 指向炮塔 [6,2]
	var turret: int = _place_factory_at(w, blueprint, Vector2i(6, 2))
	_spawn_enemy(w)
	return {"world": w, "pump": pump, "turret": turret, "atk": w.get_component(turret, &"Attack")}


func _stock(world, id: int, rid: StringName) -> int:
	var buf = world.get_component(id, &"ResourceBuffer")
	if buf == null:
		return -1
	return buf.count_of(rid)


# ---------------------------------------------------------------- 入口

func _run() -> int:
	print("======== 弹药与水效果消费端（任务 6）========")
	_config = GameConfig.load_all()
	_ok(_config != null, "GameConfig.load_all() 成功")
	if _config == null:
		return 1

	_t1_thirsty_stall()
	_t2_hydro_none()
	_t3_love_cooldown()
	_t4_dry_fire()
	_t5_table()
	_t6_deliver_routing()
	_t7_production()
	_t8_reject_edge()

	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	return _failures


# ================================================================ T1 嗜水断水停射

func _t1_thirsty_stall() -> void:
	print("== T1: 嗜水（hydro_thirsty）断水停射，接水当帧恢复 ==")
	var s: Dictionary = _turret_world(false, "gun_turret_heavy")
	var w = s["world"]
	var turret: int = s["turret"]
	var atk = s["atk"]
	_ok(turret != 0 and atk != null, "重炮塔（嗜水）落位 [6,2]（实体 %d）" % turret)
	_ok(String(atk.hydro) == "hydro_thirsty", "前置：hydro=hydro_thirsty（实际 %s）" % String(atk.hydro))
	_ok(not w.is_watered(turret), "前置：断水（is_watered=false）")
	var shots := 0
	for i in 20: # 2.0 秒 ≫ 冷却 1.2
		_clear_projectiles(w)
		w.tick(DT)
		shots += _shots(w)
	_ok(shots == 0, "断水 2.0 秒零发射（实际 %d 发）" % shots)
	_ok(atk.ammo >= 0 and atk.cooldown_left <= atk.cooldown,
		"断水停摆不烧冷却（cooldown_left=%.2f ≤ 基础 %.2f）" % [atk.cooldown_left, atk.cooldown])
	# 接水：供水当帧即恢复射击
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_place(w, "pipe", [[6, 3]], [0, -1])
	_ok(w.is_watered(turret), "接水后 is_watered=true（同一 tick 内重算）")
	_clear_projectiles(w)
	atk.cooldown_left = 0.0
	w.tick(DT)
	_ok(_shots(w) == 1, "供水当帧恢复射击（本 tick %d 发）" % _shots(w))
	# 拆掉建筑侧管 → 再次断水 → 停射
	w.push_command({"type": "remove_line", "cells": [[6, 3]]})
	w.tick(DT)
	_ok(not w.is_watered(turret), "拆管当帧停水")
	shots = 0
	for i in 20:
		_clear_projectiles(w)
		w.tick(DT)
		shots += _shots(w)
	_ok(shots == 0, "再次断水 → 再次停射（%d 发）" % shots)


# ================================================================ T2 漠水无感

func _t2_hydro_none() -> void:
	print("== T2: 漠水（hydro_none）无感——供不供水都照常打 ==")
	var s: Dictionary = _turret_world(false)
	var w = s["world"]
	var turret: int = s["turret"]
	var atk = s["atk"]
	atk.hydro = &"hydro_none" # 组件字段即契约：漠水基因
	for i in 6:
		w.deliver_ore(turret) # 满弹：只看 hydro 影响
	_ok(atk.ammo == 6, "前置：弹药 6（实际 %d）" % atk.ammo)
	var r: Dictionary = _fire_once(w, atk)
	_ok(int(r["shots"]) == 1 and is_equal_approx(float(r["damage"]), 6.0),
		"漠水 + 无供水：正常发射，伤害 6（实际 %.1f）" % float(r["damage"]))
	_ok(is_equal_approx(float(r["cooldown"]), 0.8),
		"漠水 + 无供水：冷却 = 基础 0.8（实际 %.3f）" % float(r["cooldown"]))
	var gap_dry: int = _min_shot_gap(w, atk, 30)
	# 接水：漠水不受供水影响
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_place(w, "pipe", [[6, 3]], [0, -1])
	_ok(w.is_watered(turret), "前置：接水后 is_watered=true")
	for i in 6:
		w.deliver_ore(turret)
	r = _fire_once(w, atk)
	_ok(int(r["shots"]) == 1 and is_equal_approx(float(r["damage"]), 6.0),
		"漠水 + 有供水：伤害仍 6（实际 %.1f）" % float(r["damage"]))
	_ok(is_equal_approx(float(r["cooldown"]), 0.8),
		"漠水 + 有供水：冷却仍 0.8（实际 %.3f）" % float(r["cooldown"]))
	var gap_wet: int = _min_shot_gap(w, atk, 30)
	# 9 tick（0.9 秒）：0.8 冷却在 dt=0.1 下逐 tick 递减后残留 ~1e-16 > 0，多走 1 tick
	# —— 量化误差恒定，故「供水前后同为 9」即可证明漠水无感（不掺 ×0.8 与 ×2）。
	_ok(gap_dry == 9 and gap_wet == 9,
		"漠水：供水前后实测间隔相同（%d / %d tick，dt=0.1）" % [gap_dry, gap_wet])


# ================================================================ T3 喜水冷却 ×0.8

func _t3_love_cooldown() -> void:
	print("== T3: 喜水（hydro_love）有水 → 实际冷却 ×0.8（实测计时，不改字段） ==")
	var s: Dictionary = _turret_world(true) # 炮塔蓝图自带 hydro_love
	var w = s["world"]
	var turret: int = s["turret"]
	var atk = s["atk"]
	_ok(String(atk.hydro) == "hydro_love", "前置：炮塔 hydro=hydro_love（实际 %s）" % String(atk.hydro))
	_ok(w.is_watered(turret), "前置：炮塔已接水")
	for i in 6:
		w.deliver_ore(turret)
	var r: Dictionary = _fire_once(w, atk)
	_ok(is_equal_approx(float(r["cooldown"]), 0.8 * 0.8),
		"有水 + 有弹：生效冷却 = 0.8×0.8 = 0.64（实际 %.3f）" % float(r["cooldown"]))
	_ok(is_equal_approx(float(atk.cooldown), 0.8),
		"组件 base cooldown 字段保持 0.8（加成只在生效值上，不写回字段）")
	var gap: int = _min_shot_gap(w, atk, 30)
	_ok(gap == 7, "实测发射间隔 7 tick = 0.7 秒（0.64 按 0.1 步长量化；实际 %d）" % gap)
	# 对照：同蓝图断水 → 基础 0.8 冷却
	var s2: Dictionary = _turret_world(false)
	var w2 = s2["world"]
	var atk2 = s2["atk"]
	for i in 6:
		w2.deliver_ore(s2["turret"])
	var r2: Dictionary = _fire_once(w2, atk2)
	_ok(is_equal_approx(float(r2["cooldown"]), 0.8),
		"对照（喜水断水）：生效冷却 = 0.8（实际 %.3f）" % float(r2["cooldown"]))
	var gap2: int = _min_shot_gap(w2, atk2, 30)
	# 0.8 冷却逐 tick 递减后残留正数（浮点），故量化到 9 tick = 0.9 秒；与喜水的 7 明确区分。
	_ok(gap2 == 9, "对照实测间隔 9 tick = 0.9 秒（实际 %d，比喜水的 7 tick 慢）" % gap2)


# ================================================================ T4 断弹惩罚

func _t4_dry_fire() -> void:
	print("== T4: 断弹（ammo=0）→ 冷却 ×2 且伤害 ×0.5，有弹恢复 ==")
	var s: Dictionary = _turret_world(false) # 喜水但断水：排除喜水加成，只看断弹
	var w = s["world"]
	var turret: int = s["turret"]
	var atk = s["atk"]
	atk.hydro = &"hydro_none" # 纯断弹语境：base 0.8 / 6 伤害
	_ok(atk.ammo == 0, "前置：炮塔初始无弹 ammo=0")
	var r: Dictionary = _fire_once(w, atk)
	_ok(int(r["shots"]) == 1, "断弹仍发射（半伤空放，不是停摆）")
	_ok(is_equal_approx(float(r["damage"]), 3.0),
		"断弹：伤害 ×0.5 → 3.0（实际 %.2f）" % float(r["damage"]))
	_ok(is_equal_approx(float(r["cooldown"]), 1.6),
		"断弹：冷却 ×2 → 1.6（实际 %.3f）" % float(r["cooldown"]))
	_ok(int(atk.ammo) == 0, "断弹发射不产生负弹药（ammo=%d）" % int(atk.ammo))
	var gap_dry: int = _min_shot_gap(w, atk, 40)
	_ok(gap_dry == 16, "断弹实测间隔 16 tick = 1.6 秒（实际 %d）" % gap_dry)
	# 供 1 矿 → 有弹：伤害与冷却恢复，弹扣 1
	_ok(w.deliver_ore(turret) and int(atk.ammo) == 1, "投 1 矿进弹药（ammo=%d）" % int(atk.ammo))
	r = _fire_once(w, atk)
	_ok(is_equal_approx(float(r["damage"]), 6.0), "有弹：伤害 6.0（实际 %.2f）" % float(r["damage"]))
	_ok(is_equal_approx(float(r["cooldown"]), 0.8), "有弹：冷却 0.8（实际 %.3f）" % float(r["cooldown"]))
	_ok(int(atk.ammo) == 0, "每射 1 发扣 1 矿（ammo 1→%d）" % int(atk.ammo))
	var gap_ammo: int = _min_shot_gap(w, atk, 40)
	_ok(gap_ammo == 16, "弹药打完回落到断弹节奏 16 tick（实际 %d）" % gap_ammo)


# ================================================================ T5 乘算叠加表

func _t5_table() -> void:
	print("== T5: 喜水 ×0.8 与断弹 ×2 乘算叠加（四态表钉死语义） ==")
	# 同一世界内先测断水两态 → 接水 → 测有水两态（避免重建世界带来的变量差异）
	var s: Dictionary = _turret_world(false)
	var w = s["world"]
	var turret: int = s["turret"]
	var atk = s["atk"]
	# (a) 喜水 + 断水 + 有弹：0.8 base，伤害 6
	atk.ammo = 6 # 表驱动：投料路径由 T4/T6 覆盖
	var a: Dictionary = _fire_once(w, atk)
	_ok(is_equal_approx(float(a["cooldown"]), 0.8) and is_equal_approx(float(a["damage"]), 6.0),
		"喜水/断水/有弹 → 冷却 0.80、伤害 6.0（实际 %.2f / %.1f）" % [float(a["cooldown"]), float(a["damage"])])
	# (b) 喜水 + 断水 + 断弹：0.8×2 = 1.6，伤害 3
	atk.ammo = 0
	var b: Dictionary = _fire_once(w, atk)
	_ok(is_equal_approx(float(b["cooldown"]), 1.6) and is_equal_approx(float(b["damage"]), 3.0),
		"喜水/断水/断弹 → 冷却 1.60、伤害 3.0（实际 %.2f / %.1f）" % [float(b["cooldown"]), float(b["damage"])])
	# 接水 → (c) 喜水 + 有水 + 有弹：0.8×0.8 = 0.64，伤害 6
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_place(w, "pipe", [[6, 3]], [0, -1])
	_ok(w.is_watered(turret), "接水后 is_watered=true")
	atk.ammo = 6
	var c: Dictionary = _fire_once(w, atk)
	_ok(is_equal_approx(float(c["cooldown"]), 0.64) and is_equal_approx(float(c["damage"]), 6.0),
		"喜水/有水/有弹 → 冷却 0.64、伤害 6.0（两加成不互相覆盖；实际 %.3f / %.1f）"
		% [float(c["cooldown"]), float(c["damage"])])
	# (d) 喜水 + 有水 + 断弹：0.8×2×0.8 = 1.28（乘算，不是 2+0.8 之类）
	atk.ammo = 0
	var d: Dictionary = _fire_once(w, atk)
	_ok(is_equal_approx(float(d["cooldown"]), 1.28) and is_equal_approx(float(d["damage"]), 3.0),
		"喜水/有水/断弹 → 冷却 1.28（= 0.8×2×0.8）、伤害 3.0（实际 %.3f / %.1f）"
		% [float(d["cooldown"]), float(d["damage"])])
	var gap: int = _min_shot_gap(w, atk, 40)
	_ok(gap == 13, "乘算态实测间隔 13 tick = 1.3 秒（1.28 向上取整；实际 %d）" % gap)


# ================================================================ T6 deliver_ore 分流

func _t6_deliver_routing() -> void:
	print("== T6: deliver_ore 分流 + ore_rejected 信号 + 混种 N4 ==")
	var w = _new_world()
	_grant(w)
	var turret: int = _place_factory_at(w, "gun_turret", Vector2i(6, 2))
	var gen: int = _place_factory_at(w, "generator", Vector2i(8, 3))
	var asm: int = _place_factory_at(w, "assembler", Vector2i(2, 2))
	_ok(turret != 0 and gen != 0 and asm != 0, "炮塔 / 发电机 / 装配台落位")
	var rejected: Array = []
	w.ore_rejected.connect(func(eid, reason): rejected.append([int(eid), str(reason)]))
	var atk = w.get_component(turret, &"Attack")
	_ok(AttackScript.AMMO_MAX == 6, "Attack 组件弹药上限常量 = 6（实际 %d）" % AttackScript.AMMO_MAX)
	var all_ok := true
	for i in 6:
		all_ok = w.deliver_ore(turret) and all_ok
	_ok(all_ok and int(atk.ammo) == 6, "炮塔连收 6 矿填满弹药（ammo=%d）" % int(atk.ammo))
	_ok(not w.deliver_ore(turret), "弹药满 6 → 拒收（返回 false）")
	_ok(int(atk.ammo) == 6, "拒收不涨弹药（ammo=%d）" % int(atk.ammo))
	_ok(rejected.size() == 1 and int(rejected[0][0]) == turret,
		"弹药满拒收发 ore_rejected(炮塔)（%s）" % str(rejected))
	_ok(rejected.size() == 1 and str(rejected[0][1]) == "full", "reason=\"full\"（实际 %s）" % str(rejected[0][1]))
	# 发电机：无进料配方 → 拒收 + 信号（任务 5 审查转交的零反馈缺口，逻辑层到此）
	_ok(not w.deliver_ore(gen), "发电机拒收（配方无矿堆进料）")
	_ok(rejected.size() == 2 and int(rejected[1][0]) == gen and str(rejected[1][1]) == "no_feed",
		"发电机拒收发 ore_rejected(gen, no_feed)（%s）" % str(rejected))
	# 装配台：仍走 Production 分支（进库存）
	_ok(w.deliver_ore(asm) and _stock(w, asm, &"ore") == 1, "装配台收矿进库存（%d）" % _stock(w, asm, &"ore"))
	# 满弹炮塔的带端：块滞留（不被吞）
	var w2 = _new_world()
	_grant(w2)
	var t2: int = _place_factory_at(w2, "gun_turret", Vector2i(6, 2))
	var atk2 = w2.get_component(t2, &"Attack")
	atk2.ammo = 6
	_place(w2, "belt", [[6, 3]], [0, -1]) # 端头指向炮塔 [6,2]
	_set_items(w2, Vector2i(6, 3), [1.0])
	w2.tick(DT)
	_ok(_items(w2, Vector2i(6, 3)).size() == 1, "弹药满：矿块留在带端等待（不吞不丢）")
	# 有弹空间的带端：块进弹药并从带消失
	var w3 = _new_world()
	_grant(w3)
	var t3: int = _place_factory_at(w3, "gun_turret", Vector2i(6, 2))
	_place(w3, "belt", [[6, 3]], [0, -1])
	_set_items(w3, Vector2i(6, 3), [1.0])
	w3.tick(DT)
	var atk3 = w3.get_component(t3, &"Attack")
	_ok(_items(w3, Vector2i(6, 3)).is_empty() and int(atk3.ammo) == 1,
		"端头对接炮塔：块进弹药（ammo=%d）并离开带上" % int(atk3.ammo))
	# 设计裁定 N4：DNA 混种（Attack + Production）矿先填弹药，不进合成库存
	var w4 = _new_world()
	_grant(w4)
	var asm4: int = _place_factory_at(w4, "assembler", Vector2i(2, 2))
	var hybrid_attack := AttackScript.new()
	hybrid_attack.damage = 5.0
	hybrid_attack.cooldown = 1.0
	hybrid_attack.range = 100.0
	w4.add_component(asm4, hybrid_attack)
	var hyb_prod = w4.get_component(asm4, &"Production")
	_ok(hyb_prod != null, "混种实体同时带 Attack 与 Production")
	_ok(w4.deliver_ore(asm4), "混种实体收矿 → 接收")
	_ok(int(hybrid_attack.ammo) == 1, "混种：矿进弹药（ammo=%d）" % int(hybrid_attack.ammo))
	_ok(_stock(w4, asm4, &"ore") == 0, "混种：矿不进合成库存（stock=%d）" % _stock(w4, asm4, &"ore"))
	# 混种弹药满：拒收，也不落到库存（不回落 Production 分支）
	hybrid_attack.ammo = 6
	_ok(not w4.deliver_ore(asm4), "混种弹药满 → 拒收（不回落库存）")
	_ok(_stock(w4, asm4, &"ore") == 0, "混种弹药满后库存仍 0（%d）" % _stock(w4, asm4, &"ore"))


func _set_items(world, cell: Vector2i, arr: Array) -> void:
	var c = world.grid.get_cell(cell)
	c.belt_items.clear()
	for v in arr:
		c.belt_items.append(float(v))


func _items(world, cell: Vector2i) -> Array:
	var out: Array = []
	var c = world.grid.get_cell(cell)
	if c == null:
		return out
	for v in c.belt_items:
		out.append(float(v))
	return out


# ================================================================ T7 生产端

func _t7_production() -> void:
	print("== T7: 生产端——嗜水断水不开工、喜水有水 interval×0.8 ==")
	# (a) 嗜水矿机：断水不开工（与欠料同路径），接水恢复
	var w = _new_world()
	_grant(w)
	var lg = w.get_system("LogisticsSystem")
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	# 泵在放置当帧就已扣电开工：把周期拉到极大 → 保持 active（仍是供水种子）且不再扣电，
	# 这样后面「是否扣电」只反映矿机，不被泵的 1 电/秒稀释。
	_freeze_production(w, pump)
	var miner: int = _place_factory_at(w, "miner", Vector2i(8, 3))
	_ok(pump != 0 and miner != 0 and lg != null, "水泵 [4,3] / 矿机 [8,3] 落位")
	var prod = w.get_component(miner, &"Production")
	prod.hydro = &"hydro_thirsty" # 矿机蓝图是漠水，这里验嗜水分支
	# 矿机放置当帧已按默认 hydro_none 开工过一次：清零再测嗜水分支（不是本任务逻辑）
	prod.active = false
	prod.progress = 0.0
	var power0: int = w.state.get_amount(&"power")
	_ticks(w, 40) # 4.0 秒 ≫ 周期 1.5
	_ok(not prod.active and prod.progress == 0.0,
		"嗜水断水：不开工（active=false, progress=0）")
	_ok(lg.buffer_of(miner) == 0, "嗜水断水：无产出（缓冲 %d）" % lg.buffer_of(miner))
	_ok(w.state.get_amount(&"power") == power0, "嗜水断水：不扣电（power 停在 %d）" % w.state.get_amount(&"power"))
	# 接水：泵 → 管链 → 矿机（[7,3] dir(1,0) 指向 [8,3]）
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_place(w, "pipe", [[6, 3], [7, 3]], [1, 0])
	_ok(w.is_watered(miner), "接水后 is_watered=true")
	w.tick(DT)
	_ok(prod.active, "嗜水有水：立即开工（active=true）")
	_ticks(w, 16) # 1.6 秒 > 周期 1.5
	_ok(lg.buffer_of(miner) >= 2, "嗜水有水：正常产出（缓冲 %d）" % lg.buffer_of(miner))
	_ok(w.state.get_amount(&"power") < power0, "嗜水有水：正常扣电（%d→%d）" % [power0, w.state.get_amount(&"power")])
	# 断水：在途周期照常做完（不冻结/不退款），之后不再开新周期
	_ok(prod.interval > 0.0, "前置：矿机 interval=%.2f（未被改写）" % prod.interval)
	w.push_command({"type": "remove_line", "cells": [[7, 3]]})
	w.tick(DT)
	_ok(not w.is_watered(miner), "拆建筑侧管 → 断水")
	_ticks(w, 20) # 2.0 秒：让在途周期走完
	_ok(not prod.active, "断水：在途周期做完后停摆（active=false）")
	var power_cut: int = w.state.get_amount(&"power")
	_ticks(w, 40)
	_ok(not prod.active, "断水后 4 秒内不再开新周期")
	_ok(w.state.get_amount(&"power") == power_cut, "断水后不再扣电（power 停在 %d）" % w.state.get_amount(&"power"))

	# (b) 喜水装配台：有水 interval×0.8（实测周期），组件字段保持 3.0
	var s_wet: Dictionary = _assembler_world(true)
	var wet_interval: float = s_wet["prod"].interval
	var wet_ticks: int = _measure_cycle(s_wet["world"], s_wet["asm"])
	var s_dry: Dictionary = _assembler_world(false)
	var dry_ticks: int = _measure_cycle(s_dry["world"], s_dry["asm"])
	_ok(is_equal_approx(wet_interval, 3.0), "喜水装配台 base interval 保持 3.0（实际 %.2f）" % wet_interval)
	# 计数口径：开工那一 tick 已经推进一次 progress，故「开工后续 tick 数」= 完成所需 +1/-1。
	# 喜水有水：阈值 2.4 → 24 次推进完成 = 23 个后续 tick。
	_ok(wet_ticks == 23, "喜水有水：实测周期 23+1 tick = 2.4 秒（3.0×0.8；实际 %d+1）" % wet_ticks)
	# 对照（断水）：阈值 3.0 → 30 次推进完成 = 29 个后续 tick。
	_ok(dry_ticks == 29,
		"对照（喜水断水）：实测周期 %d+1 tick = 3.0 秒（无加成、无惩罚）" % dry_ticks)
	_ok(is_equal_approx(s_dry["prod"].interval, 3.0),
		"喜水断水：interval 字段仍 3.0（实际 %.2f）" % s_dry["prod"].interval)


## 装配台测试世界：泵 [4,3] + 装配台 [8,3] + 3 矿库存 + 20 电；watered 时铺供水管。
func _assembler_world(watered: bool) -> Dictionary:
	var w = _new_world()
	_grant(w)
	w.state.resources[&"power"] = 20
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	if watered:
		_place(w, "pipe", [[5, 3]], [-1, 0])
		_place(w, "pipe", [[6, 3], [7, 3]], [1, 0]) # [7,3] dir(1,0) 指向装配台 [8,3]
	var asm: int = _place_factory_at(w, "assembler", Vector2i(8, 3))
	for i in 3:
		w.deliver_ore(asm)
	return {"world": w, "pump": pump, "asm": asm, "prod": w.get_component(asm, &"Production")}


## 实测一个完整生产周期（tick 数）：开工帧后累计 progress 到产出。
func _measure_cycle(w, id: int) -> int:
	var prod = w.get_component(id, &"Production")
	var guard := 0
	while not prod.active and guard < 10:
		w.tick(DT)
		guard += 1
	if not prod.active:
		return -1
	var ticks := 0
	while prod.active and ticks < 200:
		w.tick(DT)
		ticks += 1
	return ticks


# ================================================================ T8 ore_rejected 边沿触发

## 审查重要项：ore_rejected 原本是电平（每 tick 重试交付都发）→ 10Hz 连发，任务 7 按它
## 驱动渲染反馈会持续闪。本用例钉死边沿语义：
##   (a) 同一滞留在端头的块连跑 30 tick（30 次重试交付）→ 信号只发 1 次；
##   (b) 打光弹药 → 块被收下（退出拒收态）→ 再填满 → 再拒收能再发（「满弹→打光→再收」）；
##   (c) 同一实体 reason 从 full 变 no_feed → 算新边沿再发；之后同因仍只发 1 次。
func _t8_reject_edge() -> void:
	print("== T8: ore_rejected 边沿触发（同因连发 1 次 / 变因再发 / 恢复后再拒收再发）==")
	var w = _new_world()
	_grant(w)
	var turret: int = _place_factory_at(w, "gun_turret", Vector2i(6, 2))
	var atk = w.get_component(turret, &"Attack")
	_ok(turret != 0 and atk != null, "炮塔落位 [6,2]（实体 %d）" % turret)
	atk.ammo = 6
	_place(w, "belt", [[6, 3]], [0, -1]) # 端头 [6,3] dir(0,-1) → 指向炮塔 [6,2]
	_set_items(w, Vector2i(6, 3), [1.0])
	var rejected: Array = []
	w.ore_rejected.connect(func(eid, reason): rejected.append([int(eid), str(reason)]))
	# (a) 满弹：块滞留端头，每 tick 重试交付 → 只发一次
	_ticks(w, 30)
	_ok(rejected.size() == 1, "同因连续拒收 30 tick 只发 1 次信号（实际 %d）" % rejected.size())
	_ok(rejected.size() == 1 and int(rejected[0][0]) == turret and str(rejected[0][1]) == "full",
		"信号内容 = (炮塔, full)（实际 %s）" % str(rejected))
	_ok(_items(w, Vector2i(6, 3)).size() == 1,
		"滞留语义不变：块仍在端头（%d 块）" % _items(w, Vector2i(6, 3)).size())
	# (b) 打光弹药 → 同 tick 交付成功（清快照）→ 再填满 → 再拒收重新发
	atk.ammo = 0
	w.tick(DT)
	_ok(_items(w, Vector2i(6, 3)).is_empty() and int(atk.ammo) == 1,
		"弹药清空：滞留块被收下（ammo=%d，块离开端头）" % int(atk.ammo))
	atk.ammo = 6
	_set_items(w, Vector2i(6, 3), [1.0])
	_ticks(w, 10)
	_ok(rejected.size() == 2 and str(rejected[1][1]) == "full",
		"满弹→打光→再满：再次拒收重新发信号（共 %d 次，%s）" % [rejected.size(), str(rejected)])
	# (c) 同一实体 reason 变化：拆掉 Attack（该实体不再吃弹药）→ full 变 no_feed → 再发
	w.remove_component(turret, &"Attack")
	_ticks(w, 3)
	_ok(rejected.size() == 3 and int(rejected[2][0]) == turret and str(rejected[2][1]) == "no_feed",
		"reason 从 full 变 no_feed → 再发一次（%s）" % str(rejected))
	_ticks(w, 20)
	_ok(rejected.size() == 3, "换成 no_feed 后同因仍只发 1 次（共 %d 次）" % rejected.size())
