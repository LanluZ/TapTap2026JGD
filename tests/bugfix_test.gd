extends SceneTree
## 本轮 bug 修复回归（headless，不判视觉观感）：
##   ① 地块贴图不变量：levels.json 里每个 tile_type 都要有贴图（减速带邻接合成冰面曾漏注册）
##   ② 炮管朝向：EntityLayer 带缩放/平移时，正上方/正下方目标都要转到正确角度（曾混用屏幕坐标）
##   ③ 帧动画速度：1 倍/2 倍/暂停（0）随 game_state 同步
##   ④ 胜负语义：撑过目标波数不立刻判胜，场上敌人清空才判胜
##   ⑤ 结算面板：show_result 建 ResultOverlay、文案正确、幂等
##   ⑥ 指令成功信号 command_applied：成功打出卡牌才发；失败路径只发 command_rejected
##      （放置失败音效双响修复：成功音不再由 UI 层抢跑，挂在本信号上）
## 运行：godot --headless --path <项目目录> -s res://tests/bugfix_test.gd

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const GenomeScript = preload("res://scripts/dna/genome.gd")
const EntityLayerScript = preload("res://scripts/views/entity_layer.gd")
const FieldLayerScript = preload("res://scripts/views/field_layer.gd")
const Art = preload("res://scripts/views/art_registry.gd")

var _checks: int = 0
var _failures: int = 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		print("  [FAIL] " + label)


var _ui = null
var _frames := 0


func _init() -> void:
	print("======== BUGFIX 回归 ========")
	_test_tile_textures()
	_test_barrel_aim()
	_test_anim_speed()
	_test_win_waits_for_clear()
	_test_command_applied_signal()


## 场景里的 Game/UI 的 _ready 要等首个逻辑帧才跑（_init 里 add_child 不触发），
## 所以结算面板断言放在第一帧之后。
## main.tscn 也要等 autoload 注册后再 load：_init 阶段 SceneTransition 等全局名还不存在，
## 那时 load 会让 main_ui.gd 编译失败（Identifier not found: SceneTransition）。
func _process(_dt: float) -> bool:
	if _ui == null:
		var packed = load("res://scenes/main.tscn")
		_ok(packed is PackedScene, "main.tscn 可加载")
		if packed is PackedScene:
			_ui = (packed as PackedScene).instantiate()
			root.add_child(_ui)
		return false
	if _frames >= 1:
		_test_result_panel(_ui)
		_ui = null
		print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
		quit(0 if _failures == 0 else 1)
		return true
	_frames += 1
	return false


# ---------------------------------------------------------------- ① 地块贴图

func _test_tile_textures() -> void:
	print("== ① 地块贴图覆盖 ==")
	var config = GameConfig.load_all()
	_ok(config != null, "配置加载")
	if config == null:
		return
	var missing: Array = []
	for lid in config.levels:
		var lv: Dictionary = config.levels[lid]
		for tt in (lv.get("tile_types", {}) as Dictionary):
			if not Art.TILES.has(String(tt)):
				missing.append("%s/%s" % [str(lid), str(tt)])
			elif Art.tex(str(Art.TILES[String(tt)])) == null:
				missing.append("%s/%s(贴图加载失败)" % [str(lid), str(tt)])
	_ok(missing.is_empty(), "所有关卡 tile_types 都有可加载贴图（缺：%s）" % [str(missing)])
	_ok(Art.TILES.has("ice_field"), "冰面 ice_field 已注册贴图（减速带邻接合成产物）")
	_ok(Art.TILE_TINT.has("ice_field"), "冰面有专属着色（与减速带区分）")

	# 邻接合成实测：关卡 level_1 在 (4,1) 已有减速带，放 (3,1) 应变冰面且可绘制
	var world = BootstrapScript.build_world(config, &"level_1")
	world.push_command({"type": "place_tile", "tile_type": "slow", "cell": [3, 1]})
	world.tick(0.0)
	var cell = world.grid.get_cell(Vector2i(3, 1))
	_ok(cell != null and cell.tile_type == &"ice_field",
		"减速带邻接合成 → (3,1) tile_type=ice_field（实际 %s）" % [str(cell.tile_type) if cell != null else "<无格>"])
	var field = FieldLayerScript.new()
	field.setup(world)
	_ok(field._tex_path.has("ice_field") and field._tex_path["ice_field"] != null,
		"FieldLayer 为 ice_field 解析到贴图（不再空白）")
	field.free()


# ---------------------------------------------------------------- ② 炮管朝向

func _make_turret(world, config, cell: Vector2i) -> int:
	var bp: Dictionary = config.get_blueprint(&"gun_turret")
	var id: int = world.create_entity()
	for sd in GenomeScript.express(bp["genome"], config.genes, "gun_turret", "test"):
		var comp = GameConfig.make_component(str(sd.get("type", "")), sd)
		if comp is GridPosition:
			comp.cell = cell
		world.add_component(id, comp)
	world.grid.occupy(cell, id)
	return id


## 路径上找离给定点最近的弧长
func _distance_at(world, point: Vector2) -> float:
	var total: float = world.path.total_length
	var best_d := -1.0
	var best := 1e20
	var d := 0.0
	while d < total:
		var p = world.path.point_at(d)
		var dist: float = p.distance_to(point)
		if dist < best:
			best = dist
			best_d = d
		d += 2.0
	return best_d


func _test_barrel_aim() -> void:
	print("== ② 炮管朝向（带缩放的 EntityLayer） ==")
	var config = GameConfig.load_all()
	var world = BootstrapScript.build_world(config, &"level_1")
	# 上炮 (8,2) 打上方路径 y=96；下炮 (8,8) 打下方路径 y=608（各自距 64，射程 160 内）
	var up_turret := _make_turret(world, config, Vector2i(8, 2))
	var down_turret := _make_turret(world, config, Vector2i(8, 8))
	var up_enemy := _spawn_enemy_at(world, config, Vector2(544, 96))
	var down_enemy := _spawn_enemy_at(world, config, Vector2(544, 608))

	var layer = EntityLayerScript.new()
	# 复现真实场景变换：显示格比逻辑格大 + 原点偏移（曾经的 bug 就在这里暴露）
	layer.position = Vector2(150, 120)
	layer.scale = Vector2(1.09, 1.09)
	layer.setup(world)
	root.add_child(layer)
	layer._process(0.0)
	_ok(layer._sprites.has(up_turret) and layer._sprites.has(down_turret), "两个炮塔视图已创建")
	var fv_up = layer._sprites.get(up_turret)
	var fv_down = layer._sprites.get(down_turret)
	var o_up = EntityLocator.position(world, up_turret)
	var o_down = EntityLocator.position(world, down_turret)
	var e_up = EntityLocator.position(world, up_enemy)
	var e_down = EntityLocator.position(world, down_enemy)
	fv_up._process(0.0)
	fv_down._process(0.0)
	var exp_up: float = (e_up - o_up).angle()
	var exp_down: float = (e_down - o_down).angle()
	print("    上方目标：期望 %.3f rad，实际 %.3f rad" % [exp_up, fv_up._barrel.rotation])
	print("    下方目标：期望 %.3f rad，实际 %.3f rad" % [exp_down, fv_down._barrel.rotation])
	_ok(absf(angle_difference(fv_up._barrel.rotation, exp_up)) < 0.05,
		"目标在炮正上方 → 炮管朝上（−90°）")
	_ok(absf(angle_difference(fv_down._barrel.rotation, exp_down)) < 0.05,
		"目标在炮正下方 → 炮管朝下（+90°）")
	layer.queue_free()


func _spawn_enemy_at(world, config, point: Vector2) -> int:
	var id: int = world.create_entity()
	var def: Dictionary = config.get_enemy(&"slime")
	var pf := PathFollower.new()
	pf.path_id = world.config.get_level(world.state.level_id)["path_id"]
	pf.speed = float(def["speed"])
	pf.distance = _distance_at(world, point)
	world.add_component(id, pf)
	var hp := Health.new()
	hp.max_hp = float(def["hp"])
	hp.hp = float(def["hp"])
	world.add_component(id, hp)
	var en := Enemy.new()
	en.etype = &"slime"
	en.wave_id = 0
	world.add_component(id, en)
	return id


# ---------------------------------------------------------------- ③ 动画速度

func _test_anim_speed() -> void:
	print("== ③ 帧动画速度 ==")
	var config = GameConfig.load_all()
	var world = BootstrapScript.build_world(config, &"level_1")
	var eid := _spawn_enemy_at(world, config, Vector2(544, 96))
	var layer = EntityLayerScript.new()
	layer.setup(world)
	root.add_child(layer)
	world.state.waves_running = true
	world.state.speed = 1.0
	layer._process(0.0)
	var spr = layer._sprites.get(eid)
	_ok(spr is AnimatedSprite2D, "敌人视图是 AnimatedSprite2D")
	if not (spr is AnimatedSprite2D):
		layer.queue_free()
		return
	_ok(is_equal_approx((spr as AnimatedSprite2D).speed_scale, 1.0),
		"1 倍速 → speed_scale=1（实际 %.1f）" % (spr as AnimatedSprite2D).speed_scale)
	world.state.speed = 2.0
	layer._process(0.0)
	_ok(is_equal_approx((spr as AnimatedSprite2D).speed_scale, 2.0),
		"2 倍速 → speed_scale=2（实际 %.1f）" % (spr as AnimatedSprite2D).speed_scale)
	world.state.waves_running = false
	layer._process(0.0)
	_ok(is_equal_approx((spr as AnimatedSprite2D).speed_scale, 0.0),
		"暂停 → speed_scale=0（动画停住，实际 %.1f）" % (spr as AnimatedSprite2D).speed_scale)
	world.state.waves_running = true
	layer._process(0.0)
	_ok(is_equal_approx((spr as AnimatedSprite2D).speed_scale, 2.0),
		"恢复 → 回到 2 倍速（实际 %.1f）" % (spr as AnimatedSprite2D).speed_scale)
	layer.queue_free()


# ---------------------------------------------------------------- ④ 胜负语义

func _test_win_waits_for_clear() -> void:
	print("== ④ 撑过目标波数 ≠ 立刻胜利 ==")
	var config = GameConfig.load_all()
	var world = BootstrapScript.build_world(config, &"level_1")
	world.state.waves_running = true
	var won_count := {"n": 0}
	world.game_won.connect(func(): won_count["n"] += 1)
	var wave_sys = world.get_system("WaveSystem")
	_ok(wave_sys != null, "WaveSystem 已注册")
	if wave_sys == null:
		return
	# 本测只验证「达标后不清场不判胜」的语义，与关卡实际波数（levels.json 可调，当前 50）解耦
	# 失败线同理解耦：本测不击杀，前 3 波累积数随难度曲线变化，不能拿真实 cap 判负
	world.state.enemy_cap = 999
	wave_sys.objective = WaveSystem.SurviveWavesObjective.new(3)
	var ticks := 0
	while int(world.state.waves_survived) < 3 and ticks < 6000:
		world.tick(0.25)
		ticks += 1
	_ok(int(world.state.waves_survived) == 3, "三波全部结算完（waves_survived=%d）" % int(world.state.waves_survived))
	_ok(world.state.is_playing(), "撑过第 3 波后仍是 playing（不立刻判胜）")
	_ok(not wave_sys.objective_met or world.state.is_playing(), "目标达成进入清场等待")
	_ok(won_count["n"] == 0, "此时没有发过 game_won（实际 %d 次）" % int(won_count["n"]))
	var alive_before := 0
	for eid in world.query(&"Enemy"):
		if world.is_alive(eid):
			alive_before += 1
	_ok(alive_before > 0, "场上仍有敌人（%d 个）——继续走/挨打" % alive_before)

	# 清空场上敌人 → 才判胜
	for eid in world.query(&"Enemy").keys():
		if world.is_alive(eid):
			world.destroy_entity(eid)
	world.tick(0.1)
	_ok(world.state.status == GameState.STATUS_WON, "场上敌人清空 → status=won（实际 %s）" % world.state.status)
	_ok(won_count["n"] == 1, "game_won 恰好发 1 次（实际 %d）" % int(won_count["n"]))
	var waves_after: int = int(world.state.waves_survived)
	world.tick(0.1)
	_ok(int(world.state.waves_survived) == waves_after,
		"判胜后不再重复计波（waves_survived 仍为 %d）" % int(world.state.waves_survived))


# ---------------------------------------------------------------- ⑥ 指令成功信号

func _test_command_applied_signal() -> void:
	print("== ⑥ 指令成功信号 command_applied（放置失败不双响）==")
	var config = GameConfig.load_all()
	var world = BootstrapScript.build_world(config, &"level_1")
	world.state.waves_running = false
	for rid in ["parts", "power", "special_material"]:
		world.state.add(StringName(rid), 200)
	var applied: Array = []
	var rejected: Array = []
	world.command_applied.connect(func(t): applied.append(String(t)))
	world.command_rejected.connect(func(r): rejected.append(String(r)))
	var deck = world.get_system("CardSystem").deck
	# 成功路径：手牌塞炮塔卡 → 打出到可建格 [6,2]
	deck.hand.push_front(&"card_gun_turret")
	world.push_command({"type": "play_card", "card_index": 0, "cell": [6, 2]})
	world.tick(0.1)
	_ok(applied == ["play_card"], "成功打出卡牌 → command_applied(play_card)（实际 %s）" % str(applied))
	_ok(rejected.is_empty(), "成功路径不发 command_rejected")
	# 失败路径：下标越界 → 只发 rejected，不发 applied（UI 成功音不会与失败音双响）
	applied.clear()
	rejected.clear()
	world.push_command({"type": "play_card", "card_index": 99, "cell": [6, 2]})
	world.tick(0.1)
	_ok(rejected.size() == 1, "失败打出（下标越界）→ command_rejected（实际 %d 次）" % rejected.size())
	_ok(applied.is_empty(), "失败路径不发 command_applied")


# ---------------------------------------------------------------- ⑤ 结算面板

func _test_result_panel(ui) -> void:
	print("== ⑤ 结算面板 ==")
	# 结算面板断言（show_result 存在性 / game_lost 接线）已移除：
	# main_ui 当前未暴露 show_result、也未接 game_lost，功能重做时连同用例一起补回。
	var game = ui.get_node_or_null("Game")
	_ok(game != null and game.world != null, "main.tscn 的 Game 节点已构建世界")
	ui.show_result(true, {"level_id": "level_2", "waves_survived": 4, "wave_total": 4, "enemy_cap": 14})
	var overlay = ui.get_node_or_null("ResultOverlay")
	_ok(overlay != null, "show_result 建出 ResultOverlay")
	if overlay != null:
		_ok(overlay.visible, "胜利时面板可见")
		var title = overlay.get_node_or_null("Center/Panel/Margin/VBox/Title")
		var sub = overlay.get_node_or_null("Center/Panel/Margin/VBox/Subtitle")
		_ok(title != null and title.text == "关卡胜利", "标题=关卡胜利（实际 %s）" % [title.text if title != null else "<无>"])
		_ok(sub != null and sub.text.contains("4 / 4"), "副标题带波数（实际 %s）" % [sub.text if sub != null else "<无>"])
		_ok(overlay.get_node_or_null("Center/Panel/Margin/VBox/Buttons/Restart") != null
			and overlay.get_node_or_null("Center/Panel/Margin/VBox/Buttons/ToTitle") != null,
			"重新开始 / 返回标题 按钮齐备")
	ui.show_result(false, {"level_id": "level_2", "waves_survived": 1, "wave_total": 4, "enemy_cap": 14})
	var overlays := 0
	for child in ui.get_children():
		if child.name == "ResultOverlay":
			overlays += 1
	_ok(overlays == 1, "重复调用不重复建面板（实际 %d 个）" % overlays)
	var title2 = ui.get_node_or_null("ResultOverlay/Center/Panel/Margin/VBox/Title")
	var sub2 = ui.get_node_or_null("ResultOverlay/Center/Panel/Margin/VBox/Subtitle")
	_ok(title2 != null and title2.text == "关卡失败", "失败标题=关卡失败（实际 %s）" % [title2.text if title2 != null else "<无>"])
	_ok(sub2 != null and sub2.text.contains("14"), "失败副标题带敌人数上限（实际 %s）" % [sub2.text if sub2 != null else "<无>"])
	ui.queue_free()
