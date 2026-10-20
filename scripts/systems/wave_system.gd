class_name WaveSystem
extends System
## #2 波次（§5）：按关卡配置刷怪；统计路径敌人数与每波进度；
## 判定波次完成（该波刷出的敌人 laps_done ≥ 1 或已死亡——§5 明确的裁定，
## 对应策划案待确认 #1）与失败（路径敌人数 > 关卡 enemy_cap）。
## 关卡目标走统一 Objective 接口（§6），首个实现 SurviveWavesObjective。


## 关卡目标统一接口（§6「预留自定义接口」）。
class Objective extends RefCounted:
	func is_met(_waves_survived: int) -> bool:
		return false

	func describe() -> String:
		return "Objective"


## 首个实现：撑过 N 波（策划案 §10 关卡目标）。
class SurviveWavesObjective extends Objective:
	var target_waves: int = 0

	func _init(n: int) -> void:
		target_waves = n

	func is_met(waves_survived: int) -> bool:
		return waves_survived >= target_waves

	func describe() -> String:
		return "撑过 %d 波" % target_waves


var level: Dictionary = {}
var objective = null # Objective 实例（未知目标类型时为 null 并已在 setup 报错）
var current_wave: int = 0 # 当前波（0 起）
var wave_time: float = 0.0 # 本波已进行时间（秒）
var wave_spawned: Array = [] # 本波已刷出的实体 id
var wave_resolved: Dictionary = {} # 本波已结算 id 集合（死亡或已计圈）
var groups: Array = [] # 本波刷怪组 [{enemy, count, interval, next, spawned}]
var all_spawned: bool = false
var waves_survived: int = 0
## 目标已达成（撑过目标波数），但还没判胜：产品裁定「等场上敌人全部走完/清空才算赢」。
## 置真后不再结算波次（防重复发 per_wave 返还与重复计波），由 tick 在 alive==0 时判胜。
var objective_met: bool = false


func setup(world) -> void:
	if world.config == null or world.state == null:
		push_error("WaveSystem.setup: World 未挂载 config/state")
		return
	level = world.config.get_level(world.state.level_id)
	if level.is_empty():
		return
	var od: Dictionary = level["objective"]
	match str(od.get("type", "")):
		"survive_waves":
			objective = SurviveWavesObjective.new(int(od["waves"]))
		_:
			push_error("WaveSystem.setup: 未知关卡目标类型 '%s'" % str(od.get("type", "")))
			objective = null
	_reset_wave()


func tick(world, dt: float) -> void:
	if level.is_empty():
		return
	var state = world.state
	var playing: bool = state.is_playing()
	# waves_running=false（关卡默认暂停）时不推进刷怪：dt=0 挡不住 delay=0 的首刷
	if playing and state.waves_running:
		_advance_spawning(world, dt)
	# 路径敌人数统计 + 失败判定（§6：WaveSystem 内 enemies_on_path 计数）
	var alive := 0
	for id in world.query(&"Enemy"):
		if world.is_alive(id):
			alive += 1
	state.enemies_on_path = alive
	# 上限权威源 = GameState.enemy_cap（电力可购买提升）；未接线（0）时回退关卡配置
	var cap: int = state.enemy_cap if state.enemy_cap > 0 else int(level["enemy_cap"])
	if playing and alive > cap:
		state.status = GameState.STATUS_LOST
		world.game_lost.emit()
		playing = false
	if playing:
		_update_wave_progress(world)
		# 目标已达成 → 等场上敌人清空才判胜（产品裁定：撑过波数不立刻结束）
		if objective_met and alive == 0:
			state.status = GameState.STATUS_WON
			world.game_won.emit()


func _reset_wave() -> void:
	wave_time = 0.0
	wave_spawned = []
	wave_resolved = {}
	all_spawned = false
	groups = []
	var waves: Array = level["waves"]
	if current_wave < 0 or current_wave >= waves.size():
		push_error("WaveSystem: 波次下标越界 %d / %d" % [current_wave, waves.size()])
		return
	for s in waves[current_wave]["spawns"]:
		groups.append({
			"enemy": s["enemy"], "count": int(s["count"]),
			"interval": float(s["interval"]), "next": float(s["delay"]), "spawned": 0,
		})


func _advance_spawning(world, dt: float) -> void:
	wave_time += dt
	for g in groups:
		while int(g["spawned"]) < int(g["count"]) and wave_time >= float(g["next"]):
			_spawn_enemy(world, StringName(g["enemy"]))
			g["spawned"] = int(g["spawned"]) + 1
			g["next"] = float(g["next"]) + float(g["interval"])
	all_spawned = true
	for g in groups:
		if int(g["spawned"]) < int(g["count"]):
			all_spawned = false
			break


func _update_wave_progress(world) -> void:
	# 目标达成后不再结算：否则每帧都会重复计波 / 重复发地块 per_wave 返还
	if objective_met:
		return
	# 结算：死亡或 laps_done ≥ 1 都算“走完一圈”（§5 波次定义 + 说明）
	for id in wave_spawned:
		if wave_resolved.has(id):
			continue
		if not world.is_alive(id):
			wave_resolved[id] = true
			continue
		var en = world.get_component(id, &"Enemy")
		if en != null and en.laps_done >= 1:
			wave_resolved[id] = true
	if not all_spawned or wave_spawned.is_empty():
		return
	if wave_resolved.size() < wave_spawned.size():
		return
	# —— 本波完成 ——
	# 地块每波结算（§19.2）：场上每块地块按 tile_types.per_wave 返还零件，地块从装饰变投资
	var tile_types: Dictionary = level.get("tile_types", {})
	var grant := 0
	for cell in world.grid.cells:
		var gc = world.grid.cells[cell]
		if gc.tile_type == &"":
			continue
		grant += int((tile_types.get(gc.tile_type, {}) as Dictionary).get("per_wave", 0))
	if grant > 0:
		world.state.add(&"parts", grant)
	waves_survived += 1
	world.state.waves_survived = waves_survived
	world.wave_completed.emit(current_wave)
	if objective != null and objective.is_met(waves_survived):
		# 不立刻判胜：产品裁定「等场上敌人全部走完/清空」——由 tick 在 alive==0 时置 WON
		objective_met = true
		return
	current_wave += 1
	if current_wave >= (level["waves"] as Array).size():
		push_error("WaveSystem: 波次已耗尽但目标未达成（GameConfig 交叉校验应已拦截此配置）")
		return
	_reset_wave()


func _spawn_enemy(world, enemy_id: StringName) -> int:
	var def: Dictionary = world.config.get_enemy(enemy_id)
	if def.is_empty():
		return 0
	var id: int = world.create_entity()
	var pf := PathFollower.new()
	pf.path_id = level["path_id"]
	pf.distance = 0.0
	pf.speed = float(def["speed"])
	world.add_component(id, pf)
	var hp := Health.new()
	hp.max_hp = float(def["hp"])
	hp.hp = float(def["hp"])
	world.add_component(id, hp)
	var en := Enemy.new()
	en.wave_id = current_wave
	en.etype = enemy_id
	en.elite = bool(def["elite"])
	en.flying = bool(def.get("flying", false))
	en.loot_id = def["loot_id"]
	en.loot_amount = int(def["loot_amount"])
	world.add_component(id, en)
	wave_spawned.append(id)
	return id
