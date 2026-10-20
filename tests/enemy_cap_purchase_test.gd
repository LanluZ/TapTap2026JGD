extends SceneTree
## 电力购买「路径敌人上限」回归（headless，不判视觉观感）：
##   ① 价格公式：round(ln(e + 已购次数×3))，次数从 0 起
##   ② 购买成交：扣电 + 上限 +2 + 次数 +1
##   ③ 买不起：钱包/上限/次数全不动
##   ④ 判败阈值跟 GameState.enemy_cap 走：购买后放宽；未接线（0）回退关卡配置
## 运行：godot --headless --path <项目目录> -s res://tests/enemy_cap_purchase_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const DT := 0.1

var _checks: int = 0
var _failures: int = 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		print("  [FAIL] " + label)


func _init() -> void:
	print("======== 敌人上限购买（电力）========")
	_test_price()
	_test_buy()
	_test_afford_guard()
	_test_wave_cap()
	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------- ① 价格公式

func _test_price() -> void:
	print("== ① 价格序列 round(ln(e + 次数×3)) ==")
	# round 与 roundf 同为四舍五入：1, 2, 2, 2, 3×7, 4 …
	var expect := [1, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4]
	for i in expect.size():
		var got := GameState.enemy_cap_price(i)
		_ok(got == expect[i], "第 %d 次：期望 %d，实际 %d" % [i, expect[i], got])
	_ok(GameState.enemy_cap_price(0) == 1, "首件 = ln(e) = 1 电")
	_ok(GameState.enemy_cap_price(-5) == 1, "负次数按 0 处理（不返回 0/负数）")


# ---------------------------------------------------------------- ② 购买成交

func _test_buy() -> void:
	print("== ② 购买成交 ==")
	var st := GameState.new()
	st.enemy_cap = 10
	st.add(&"power", 100)
	_ok(st.buy_enemy_cap(), "电 100：首次购买成交")
	_ok(st.enemy_cap == 12, "上限 10 → 12（每次 +%d，实际 %d）" % [GameState.ENEMY_CAP_STEP, st.enemy_cap])
	_ok(st.get_amount(&"power") == 99, "扣电 1（余 %d）" % st.get_amount(&"power"))
	_ok(st.enemy_cap_buys == 1, "已购次数 0 → 1")
	_ok(st.buy_enemy_cap(), "第二次购买成交")
	_ok(st.enemy_cap == 14, "上限 12 → 14（实际 %d）" % st.enemy_cap)
	_ok(st.get_amount(&"power") == 97, "第二次扣电 2（余 %d）" % st.get_amount(&"power"))
	_ok(st.enemy_cap_buys == 2, "已购次数 1 → 2")


# ---------------------------------------------------------------- ③ 买不起

func _test_afford_guard() -> void:
	print("== ③ 买不起时不扣款 ==")
	var st := GameState.new()
	st.enemy_cap = 10
	_ok(not st.buy_enemy_cap(), "电 0：购买失败")
	_ok(st.enemy_cap == 10 and st.enemy_cap_buys == 0 and st.get_amount(&"power") == 0,
		"失败无副作用（上限 %d / 次数 %d / 电 %d）" % [st.enemy_cap, st.enemy_cap_buys, st.get_amount(&"power")])
	st.add(&"power", 1)
	_ok(st.buy_enemy_cap(), "恰 1 电（首件价）可成交")
	# 第二件要 2 电：1 电买不动
	var st2 := GameState.new()
	st2.enemy_cap = 10
	st2.enemy_cap_buys = 1
	st2.add(&"power", 1)
	_ok(not st2.buy_enemy_cap(), "第二件价 2 电、只有 1 电 → 失败")
	_ok(st2.enemy_cap == 10 and st2.get_amount(&"power") == 1, "失败不动钱包与上限")


# ---------------------------------------------------------------- ④ 判败阈值

func _test_wave_cap() -> void:
	print("== ④ 判败阈值跟随 GameState.enemy_cap ==")
	var config = GameConfig.load_all()
	_ok(config != null, "配置加载")
	if config == null:
		return
	var cap := int(config.get_level(&"level_1")["enemy_cap"])

	# 放宽 2 个名额：关卡上限 +1 个敌人不判败
	var w = BootstrapScript.build_world(config, &"level_1")
	_ok(w != null and w.state != null, "world 构建")
	if w == null or w.state == null:
		return
	w.state.waves_running = false # 关掉刷怪，计数只来自手工投放
	w.state.enemy_cap = cap + GameState.ENEMY_CAP_STEP
	for i in cap + 1:
		_spawn_test_enemy(w, config, &"slime")
	w.tick(DT)
	_ok(w.state.status == GameState.STATUS_PLAYING,
		"上限 %d（关卡 %d + %d）：在场 %d 个仍 playing（status=%s）"
		% [w.state.enemy_cap, cap, GameState.ENEMY_CAP_STEP, w.state.enemies_on_path, w.state.status])

	# 超过放宽后的上限 → 判败
	for i in GameState.ENEMY_CAP_STEP:
		_spawn_test_enemy(w, config, &"slime")
	w.tick(DT)
	_ok(w.state.status == GameState.STATUS_LOST,
		"在场 %d > 上限 %d → 判败（status=%s）" % [w.state.enemies_on_path, w.state.enemy_cap, w.state.status])

	# 未接线（0）：回退关卡配置，仍按原阈值判败
	var w0 = BootstrapScript.build_world(config, &"level_1")
	if w0 == null or w0.state == null:
		return
	w0.state.waves_running = false
	w0.state.enemy_cap = 0
	for i in cap + 1:
		_spawn_test_enemy(w0, config, &"slime")
	w0.tick(DT)
	_ok(w0.state.status == GameState.STATUS_LOST,
		"未接线（cap=0）回退关卡值 %d：在场 %d 判败" % [cap, w0.state.enemies_on_path])


# ---------------------------------------------------------------- 工具

## 手工投放一个敌人（与 smoke.gd 同构：PathFollower + Health + Enemy）。
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
