extends SceneTree
## 物流数据层与放置/拆除指令 headless 验证（任务 2/8）：
## Cell 的线路字段（line_kind/line_dir/belt_items）→ GridSystem 校验 →
## CommandSystem 的 place_line / remove_line 指令协议 → world.line_changed 信号。
## 运行：godot --headless --path <项目目录> -s res://tests/logistics_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const LineToolScript = preload("res://scripts/ui/line_tool.gd")
const LogisticsLayerScript = preload("res://scripts/views/logistics_layer.gd")
const Art = preload("res://scripts/views/art_registry.gd")
## 接线层（game.gd）：取静态纯函数 cells_with_line 测「拆除只拆有线格」的过滤（裁定 ②），
## 并裸实例化 GameScript.new()（不加载 main.tscn）测断水回执去重（NEW-3）；
## 完整场景仍是 ui_selftest 的事。
const GameScript = preload("res://scripts/game.gd")
const DT := 0.1

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false
var _config = null
var _rejects: Array = [] # 当前世界的 command_rejected 原因
var _line_events: Array = [] # [cell, kind] 二元数组记录
var _deliveries: Array = [] # ore_delivered 的 entity_id 记录（任务 3 交付 stub）


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
	var w = BootstrapScript.build_world(_config, &"level_1")
	_rejects = []
	_line_events = []
	_deliveries = []
	w.command_rejected.connect(func(r): _rejects.append(str(r)))
	w.line_changed.connect(func(c, k): _line_events.append([c, k]))
	w.ore_delivered.connect(func(e): _deliveries.append(int(e)))
	return w


# ---------------------------------------------------------------- 任务 3 测试辅助

## LogisticsSystem 查询入口（与后续任务同一入口：world.get_system("LogisticsSystem")）。
func _logi(world):
	return world.get_system("LogisticsSystem")


## 覆写某格的块位（模拟已上带/已注入的矿块）。
func _set_items(world, cell: Vector2i, arr: Array) -> void:
	var c = world.grid.get_cell(cell)
	c.belt_items.clear()
	for v in arr:
		c.belt_items.append(float(v))


## 读某格的块位副本（Array[float] → 普通 Array，便于打印/比较）。
func _items(world, cell: Vector2i) -> Array:
	var out: Array = []
	var c = world.grid.get_cell(cell)
	if c == null:
		return out
	for v in c.belt_items:
		out.append(float(v))
	return out


func _ticks(world, n: int, dt: float = 0.1) -> void:
	for i in n:
		world.tick(dt)


## 位置数组逐项近似比较（固定顺序，不排序）。
func _approx(arr: Array, expected: Array) -> bool:
	if arr.size() != expected.size():
		return false
	for i in arr.size():
		if absf(float(arr[i]) - float(expected[i])) > 0.002:
			return false
	return true


## 同格相邻块的最小间距（空/单块返回 1.0）。
func _min_gap(arr: Array) -> float:
	if arr.size() < 2:
		return 1.0
	var sorted: Array = arr.duplicate()
	sorted.sort()
	var m: float = 1.0
	for i in range(1, sorted.size()):
		m = minf(m, float(sorted[i]) - float(sorted[i - 1]))
	return m


## 开局资源补给（测试放置非免费蓝图用；免费蓝图不受影响）。
func _grant(world) -> void:
	for rid in ["parts", "power", "water", "ore", "special_material"]:
		world.state.add(StringName(rid), 200)


## 隔离生产端（任务 5 起泵会把产出写进同一个本地缓冲）：把周期拉到极大，
## 避免自动补水/补矿干扰「排水/注入速率」的精确断言。
## 生产端 → 缓冲的接线由 tests/production_test.gd 覆盖，这里只测物流侧。
func _freeze_production(world, id: int) -> void:
	var prod = world.get_component(id, &"Production")
	if prod != null:
		prod.interval = 1.0e9


## 放置工厂并返回实体 id（0 = 失败）。
func _place_factory_at(world, blueprint: String, cell: Vector2i) -> int:
	world.push_command({"type": "place_factory", "blueprint_id": blueprint, "cell": [cell.x, cell.y]})
	world.tick(DT)
	var c = world.grid.get_cell(cell)
	if c == null:
		return 0
	return int(c.occupant)


## 推入一条 place_line 指令并跑一逻辑帧，返回本次新增的拒绝数。
func _place(world, kind: String, cells: Array, dir_v: Array) -> int:
	var before: int = _rejects.size()
	world.push_command({"type": "place_line", "kind": kind, "cells": cells, "dir": dir_v})
	world.tick(DT)
	return _rejects.size() - before


## 推入一条 remove_line 指令并跑一逻辑帧，返回本次新增的拒绝数。
func _remove(world, cells: Array) -> int:
	var before: int = _rejects.size()
	world.push_command({"type": "remove_line", "cells": cells})
	world.tick(DT)
	return _rejects.size() - before


func _run() -> int:
	print("======== 物流数据层 / 放置·拆除指令测试 ========")
	_config = GameConfig.load_all()
	_ok(_config != null, "GameConfig.load_all() 成功")
	if _config == null:
		printerr("配置加载失败，后续测试无法进行")
		return 1

	print("== T0: Cell 线路字段默认值 ==")
	var w0 = _new_world()
	var c0 = w0.grid.get_cell(Vector2i(3, 3))
	_ok(c0 != null, "buildable 格 [3,3] 存在")
	_ok(c0.line_kind == &"", "新格 line_kind 为空 StringName")
	_ok(c0.line_dir == Vector2i.ZERO, "新格 line_dir 为 ZERO")
	_ok(c0.belt_items.is_empty() and c0.belt_items.is_typed(), "belt_items 是空的 Array[float]")
	_ok(not c0.has_line(), "has_line() 初始为 false")

	print("== T1: GridSystem.can_place_line / can_remove_line 校验 ==")
	var gs = w0.get_system("GridSystem")
	var ok_cells: Array = [Vector2i(2, 5), Vector2i(3, 5)]
	_ok(gs.can_place_line(w0, ok_cells, &"pipe", Vector2i(1, 0)) == "", "合法 pipe 链返回空串")
	_ok(gs.can_place_line(w0, ok_cells, &"belt", Vector2i(1, 0)) == "", "合法 belt 链返回空串")
	_ok(gs.can_place_line(w0, [Vector2i(1, 1)], &"pipe", Vector2i(1, 0)) != "", "路径格（非 buildable）被拒绝")
	_ok(gs.can_place_line(w0, [Vector2i(5, 9)], &"pipe", Vector2i(1, 0)) != "", "带地块的路径格（非 buildable）被拒绝")
	_ok(gs.can_place_line(w0, [Vector2i(99, 99)], &"pipe", Vector2i(1, 0)).find("不存在") != -1,
		"不存在的格被拒绝且原因说明「不存在」")
	_ok(gs.can_place_line(w0, ok_cells, &"wire", Vector2i(1, 0)) != "", "未知 kind 被拒绝")
	_ok(gs.can_place_line(w0, ok_cells, &"pipe", Vector2i(1, 1)) != "", "对角 dir 被拒绝")
	_ok(gs.can_place_line(w0, ok_cells, &"pipe", null) != "", "缺 dir（null）被拒绝")
	_ok(gs.can_place_line(w0, [], &"pipe", Vector2i(1, 0)) != "", "空 cells 被拒绝")
	_ok(gs.can_place_line(w0, [Vector2i(2, 5), Vector2i(2, 5)], &"pipe", Vector2i(1, 0)) != "", "重复格被拒绝")
	_ok(gs.can_remove_line(w0, [Vector2i(2, 5)]) != "", "无线格不可拆除")
	_ok(gs.can_remove_line(w0, [Vector2i(99, 99)]) != "", "不存在的格不可拆除")

	print("== T2: place_line（pipe）指令端到端 ==")
	var w2 = _new_world()
	var parts0: int = w2.state.get_amount(&"parts")
	var power0: int = w2.state.get_amount(&"power")
	w2.push_command({"type": "place_line", "kind": "pipe", "cells": [[2, 5], [3, 5]], "dir": [1, 0]})
	_ok(w2.grid.get_cell(Vector2i(2, 5)).line_kind == &"", "入队未 drain 前世界未改动（下一逻辑帧执行）")
	w2.tick(DT)
	var a2 = w2.grid.get_cell(Vector2i(2, 5))
	var b2 = w2.grid.get_cell(Vector2i(3, 5))
	_ok(a2.line_kind == &"pipe" and a2.line_dir == Vector2i(1, 0), "首格写入 pipe 与 dir (1,0)")
	_ok(b2.line_kind == &"pipe" and b2.line_dir == Vector2i(1, 0), "次格写入 pipe 与 dir (1,0)")
	_ok(_rejects.is_empty(), "合法指令无 command_rejected（实际 %d）" % _rejects.size())
	_ok(_line_events.size() == 2, "line_changed 每格一次（实际 %d）" % _line_events.size())
	_ok(_line_events.size() == 2 and _line_events[0][0] == Vector2i(2, 5) and _line_events[0][1] == &"pipe"
		and _line_events[1][0] == Vector2i(3, 5),
		"line_changed 携带 (cell, kind) 与格序一致")
	_ok(w2.state.get_amount(&"parts") == parts0 and w2.state.get_amount(&"power") == power0,
		"放置线路免费（parts %d→%d, power %d→%d）" % [parts0, w2.state.get_amount(&"parts"), power0, w2.state.get_amount(&"power")])

	print("== T3: place_line（belt）与块位数组 ==")
	var w3 = _new_world()
	_ok(_place(w3, "belt", [[4, 6], [5, 6]], [0, 1]) == 0, "belt 指令成功")
	var b3 = w3.grid.get_cell(Vector2i(4, 6))
	_ok(b3.line_kind == &"belt" and b3.line_dir == Vector2i(0, 1), "belt 写入 line_dir (0,1)")
	_ok(b3.belt_items.is_typed() and b3.belt_items.get_typed_builtin() == TYPE_FLOAT,
		"belt_items 为 Array[float]（位置 ∈ [0,1) 沿 line_dir）")
	b3.belt_items.append(0.25)
	_ok(b3.belt_items.size() == 1 and is_equal_approx(b3.belt_items[0], 0.25), "belt_items 可写入 0.25 块位")

	print("== T4: 拒绝清单（失败发 command_rejected、不改世界）==")
	var w4 = _new_world()
	_ok(_place(w4, "pipe", [[1, 1]], [1, 0]) == 1, "路径格（非 buildable）放置被拒绝")
	_ok(w4.grid.get_cell(Vector2i(1, 1)).line_kind == &"", "拒绝后路径格无线路")
	_ok(_place(w4, "pipe", [[99, 99]], [1, 0]) == 1, "不存在的格放置被拒绝")
	w4.push_command({"type": "place_factory", "blueprint_id": "generator", "cell": [4, 2]})
	w4.tick(DT)
	_ok(w4.grid.get_cell(Vector2i(4, 2)).occupant != 0, "发电机占位 [4,2]（免费蓝图）")
	_ok(_place(w4, "pipe", [[5, 2], [4, 2]], [1, 0]) == 1, "工厂占用格放置线路被拒绝")
	_ok(w4.grid.get_cell(Vector2i(5, 2)).line_kind == &"", "指令原子失败：同批 [5,2] 未被写入")
	_ok(_place(w4, "pipe", [[6, 6]], [1, 0]) == 0, "先放一条 pipe 成功")
	_ok(_place(w4, "belt", [[6, 6]], [0, 1]) == 0, "已有线路的格覆盖放置（pipe→belt）成功")
	var over4 = w4.grid.get_cell(Vector2i(6, 6))
	_ok(over4.line_kind == &"belt" and over4.line_dir == Vector2i(0, 1), "覆盖后旧 pipe 被替换为 belt (0,1)")
	_ok(_place(w4, "wire", [[7, 7]], [1, 0]) == 1, "未知 kind 的指令被拒绝")
	_ok(_place(w4, "pipe", [[7, 7]], [1, 1]) == 1, "对角 dir 的指令被拒绝")
	_ok(_place(w4, "pipe", [[7, 7]], [0, 0]) == 1, "零向量 dir 的指令被拒绝")
	_ok(_place(w4, "pipe", [], [1, 0]) == 1, "空 cells 的指令被拒绝")
	_ok(_place(w4, "pipe", [[7, 7], [7]], [1, 0]) == 1, "cells 含非法元素被拒绝")
	var before4: int = _rejects.size()
	w4.push_command({"type": "place_line", "kind": "pipe", "cells": [[8, 8]]})
	w4.tick(DT)
	_ok(_rejects.size() == before4 + 1, "缺 dir 字段的指令被拒绝")
	_ok(w4.grid.get_cell(Vector2i(7, 7)).line_kind == &"", "以上拒绝均未改动 [7,7]")
	_ok(w4.grid.get_cell(Vector2i(8, 8)).line_kind == &"", "缺 dir 的指令未改动 [8,8]")

	print("== T5: remove_line 指令 ==")
	var w5 = _new_world()
	_ok(_place(w5, "belt", [[5, 7], [6, 7]], [1, 0]) == 0, "拆除前先铺 belt")
	w5.grid.get_cell(Vector2i(5, 7)).belt_items.append(0.5)
	_line_events.clear()
	_ok(_remove(w5, [[5, 7], [6, 7]]) == 0, "在线格拆除成功")
	var d5 = w5.grid.get_cell(Vector2i(5, 7))
	_ok(d5.line_kind == &"" and d5.line_dir == Vector2i.ZERO, "拆除后 line_kind/line_dir 复位")
	_ok(d5.belt_items.is_empty(), "拆除清空 belt_items")
	_ok(w5.grid.get_cell(Vector2i(6, 7)).line_kind == &"", "链上第二格同样拆除")
	_ok(_line_events.size() == 2 and _line_events[0][1] == &"", "line_changed 以 kind=\"\" 通知拆除")
	_ok(_remove(w5, [[5, 7]]) == 1, "对无线格拆除被拒绝")
	_ok(_remove(w5, [[99, 99]]) == 1, "对不存在格拆除被拒绝")
	var before5: int = _rejects.size()
	w5.push_command({"type": "remove_line"})
	w5.tick(DT)
	_ok(_rejects.size() == before5 + 1, "缺 cells 的拆除指令被拒绝")
	_line_events.clear()
	_place(w5, "pipe", [[1, 1]], [1, 0])
	_ok(_line_events.is_empty(), "被拒绝的指令不发 line_changed")

	print("== T6: 四向 dir 与 Vector2i 形态 ==")
	var w6 = _new_world()
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var coords: Array = [Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8)]
	for i in 4:
		var dv: Vector2i = dirs[i]
		_ok(_place(w6, "belt", [coords[i]], [dv.x, dv.y]) == 0, "dir %s 的放置成功" % str(dv))
		_ok(w6.grid.get_cell(coords[i]).line_dir == dv, "dir %s 写入格 [%d,%d]" % [str(dv), coords[i].x, coords[i].y])
	w6.push_command({"type": "place_line", "kind": "pipe", "cells": [Vector2i(6, 8)], "dir": Vector2i(0, -1)})
	w6.tick(DT)
	_ok(w6.grid.get_cell(Vector2i(6, 8)).line_kind == &"pipe"
		and w6.grid.get_cell(Vector2i(6, 8)).line_dir == Vector2i(0, -1),
		"cells/dir 支持 Vector2i 形态（UI 可直接传）")

	print("== T7: 一格式一物（工厂不能压在线上，拆除后释放）==")
	var w7 = _new_world()
	_ok(_place(w7, "pipe", [[9, 8]], [1, 0]) == 0, "先在线格 [9,8] 铺 pipe")
	var before7: int = _rejects.size()
	w7.push_command({"type": "place_factory", "blueprint_id": "generator", "cell": [9, 8]})
	w7.tick(DT)
	_ok(_rejects.size() == before7 + 1, "线格上放置工厂被拒绝")
	_ok(w7.grid.get_cell(Vector2i(9, 8)).occupant == 0, "拒绝后 line 格 occupant 仍为 0")
	_ok(_remove(w7, [[9, 8]]) == 0, "拆除该线")
	w7.push_command({"type": "place_factory", "blueprint_id": "generator", "cell": [9, 8]})
	w7.tick(DT)
	_ok(w7.grid.get_cell(Vector2i(9, 8)).occupant != 0, "拆除线路后同格可放工厂（格完全释放）")

	print("== T8: 协议原文形态（[[x,y]] / [dx,dy]）与双向互斥 ==")
	var w8 = _new_world()
	var gs8 = w8.get_system("GridSystem")
	_ok(gs8.can_place_line(w8, [[2, 5], [3, 5]], "pipe", [1, 0]) == "",
		"can_place_line 直接接受协议形态 [[x,y]] / [dx,dy]（UI 拖拽提示不再误判非法）")
	_ok(gs8.can_place_line(w8, [Vector2(2.0, 5.0)], "pipe", Vector2(1, 0)) == "",
		"can_place_line 接受 Vector2 形态")
	_ok(gs8.can_place_line(w8, [[2, 5], [7]], "pipe", [1, 0]).find("非坐标") != -1,
		"非法元素（长度不足的数组）被拒绝且原因说明「非坐标」")
	_ok(gs8.can_place_line(w8, [[2, 5], [3, 5]], "pipe", [1, 1]) != "", "数组形态的对角 dir 仍被拒绝")
	_ok(_place(w8, "pipe", [[4, 6], [5, 6]], [0, 1]) == 0, "协议 [[x,y]] 形态 place_line 端到端成功")
	_ok(w8.grid.get_cell(Vector2i(4, 6)).line_kind == &"pipe"
		and w8.grid.get_cell(Vector2i(4, 6)).line_dir == Vector2i(0, 1), "端到端写入 kind/dir 正确")
	_ok(_place(w8, "pipe", [[6, 6], [6, 6]], [1, 0]) == 1, "含重复格的 place_line 仍被拒绝")
	_ok(w8.grid.get_cell(Vector2i(6, 6)).line_kind == &"", "重复格被拒后 [6,6] 无线路")
	# 反向互斥：已有工厂的格上 place_line 被拒（is_buildable 双向契约的另一半）
	w8.push_command({"type": "place_factory", "blueprint_id": "generator", "cell": [4, 2]})
	w8.tick(DT)
	_ok(w8.grid.get_cell(Vector2i(4, 2)).occupant != 0, "发电机占位 [4,2]")
	_ok(gs8.can_place_line(w8, [[4, 2]], "pipe", [1, 0]).find("占用") != -1,
		"已有工厂的格 can_place_line 拒绝且原因说明「占用」")
	_ok(_place(w8, "pipe", [[4, 2]], [1, 0]) == 1, "已有工厂的格 place_line 指令被拒")
	_ok(w8.grid.get_cell(Vector2i(4, 2)).line_kind == &"", "拒绝后工厂格上无线路")
	# 重复格拆除：去重后只拆一次、只发一次 line_changed
	_line_events.clear()
	_ok(_remove(w8, [[4, 6], [4, 6]]) == 0, "重复格 remove_line 指令被接受（去重）")
	_ok(_line_events.size() == 1, "重复格拆除只发一次 line_changed（实际 %d）" % _line_events.size())
	_ok(w8.grid.get_cell(Vector2i(4, 6)).line_kind == &"", "重复格拆除后线路已清除")

	print("======== 传送带离散矿块模拟（任务 3）========")
	var probe = _new_world()
	if _logi(probe) == null:
		_checks += 1
		_failures += 1
		printerr("  [FAIL] LogisticsSystem 未注册（world.get_system 查不到），T9~T16 全部跳过")
	else:
		_t9_advance()
		_t10_transfer()
		_t11_drop()
		_t12_jam()
		_t13_cross()
		_t14_merge()
		_t15_inject()
		_t16_deliver()
		_t17_inject_rate()
		_t18_water_supply()
		_t19_water_break()
		_t20_water_multi_pump()
		_t21_water_direction()
		_t22_pump_drain()
		_t23_water_truth_table()
		_t24_drag_end_to_end()
		_t25_drag_to_cells()
		_t26_render_data()
		_t27_product_rulings()
		_t28_corner_join()

	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	return _failures


# ================================================================ 任务 3：传送带模拟

func _t9_advance() -> void:
	print("== T9: 直线推进（带速 2 格/秒）==")
	var w = _new_world()
	_ok(_place(w, "belt", [[2, 6]], [1, 0]) == 0, "T9: 单格 belt [2,6] dir(1,0) 铺设")
	_set_items(w, Vector2i(2, 6), [0.0])
	w.tick(0.1)
	_ok(_approx(_items(w, Vector2i(2, 6)), [0.2]),
		"T9: dt=0.1 推进 0.2 格（实际 %s）" % str(_items(w, Vector2i(2, 6))))
	w.tick(0.1)
	_ok(_approx(_items(w, Vector2i(2, 6)), [0.4]),
		"T9: 再 dt=0.1 到 0.4（实际 %s）" % str(_items(w, Vector2i(2, 6))))
	w.tick(0.2)
	_ok(_approx(_items(w, Vector2i(2, 6)), [0.8]),
		"T9: dt=0.2 到 0.8（实际 %s）" % str(_items(w, Vector2i(2, 6))))
	w.tick(0.1)
	_ok(_items(w, Vector2i(2, 6)).is_empty(),
		"T9: 推到 1.0 且出口无线路 → 掉落消失（实际 %s）" % str(_items(w, Vector2i(2, 6))))


func _t10_transfer() -> void:
	print("== T10: 跨格转移（同向链插入点 0.0）==")
	var w = _new_world()
	_ok(_place(w, "belt", [[2, 6], [3, 6]], [1, 0]) == 0, "T10: 同向两格链铺设")
	_set_items(w, Vector2i(2, 6), [0.9])
	w.tick(0.1)
	_ok(_items(w, Vector2i(2, 6)).is_empty(), "T10: 转移后源格清空")
	_ok(_approx(_items(w, Vector2i(3, 6)), [0.0]),
		"T10: 同向 → 插入点 0.0（实际 %s）" % str(_items(w, Vector2i(3, 6))))
	w.tick(0.1)
	_ok(_approx(_items(w, Vector2i(3, 6)), [0.2]),
		"T10: 下一 tick 从插入点继续推进（实际 %s）" % str(_items(w, Vector2i(3, 6))))


func _t11_drop() -> void:
	print("== T11: 悬空 / 管道格出口 → 掉落 ==")
	var w = _new_world()
	_ok(_place(w, "belt", [[2, 6]], [1, 0]) == 0, "T11: 单格 belt [2,6]")
	_set_items(w, Vector2i(2, 6), [1.0])
	w.tick(DT)
	_ok(_items(w, Vector2i(2, 6)).is_empty(), "T11: 出口为空地 → 块消失")
	_ok(_deliveries.is_empty(), "T11: 空地出口不触发交付（实际 %s）" % str(_deliveries))
	_ok(_place(w, "pipe", [[3, 6]], [1, 0]) == 0, "T11: 出口格铺 pipe")
	_set_items(w, Vector2i(2, 6), [1.0])
	w.tick(DT)
	_ok(_items(w, Vector2i(2, 6)).is_empty(), "T11: 管道格出口 → 块消失（矿不串管道）")
	_ok(_deliveries.is_empty(), "T11: 管道格出口不触发交付")


func _t12_jam() -> void:
	print("== T12: 前堵后排队（间距 0.25 / 每格容量 4 / 满格等待）==")
	var w = _new_world()
	var a := Vector2i(2, 6)
	var b := Vector2i(3, 6)
	_ok(_place(w, "belt", [a], [1, 0]) == 0, "T12: [2,6] dir(1,0)")
	_ok(_place(w, "belt", [b], [-1, 0]) == 0, "T12: [3,6] dir(-1,0)（对头，互为出口、互塞满）")
	_set_items(w, a, [0.0, 0.25, 0.5, 1.0])
	_set_items(w, b, [0.0, 0.25, 0.5, 1.0])
	_ticks(w, 3)
	_ok(_approx(_items(w, a), [0.25, 0.5, 0.75, 1.0]),
		"T12: 前块堵死 → 后块压到 0.25 间距停下（实际 %s）" % str(_items(w, a)))
	_ok(_approx(_items(w, b), [0.25, 0.5, 0.75, 1.0]),
		"T12: 对向格同理（实际 %s）" % str(_items(w, b)))
	_ok(_items(w, a).size() <= 4 and _items(w, b).size() <= 4,
		"T12: 每格容量上限 4（实际 %d / %d）" % [_items(w, a).size(), _items(w, b).size()])
	_ok(_items(w, a).size() + _items(w, b).size() == 8, "T12: 满格等待不丢块（合计 8）")
	_ok(_min_gap(_items(w, a)) >= 0.25 - 0.002, "T12: 同格最小间距 ≥ 0.25（实际 %.3f）" % _min_gap(_items(w, a)))
	_ticks(w, 10)
	_ok(_approx(_items(w, a), [0.25, 0.5, 0.75, 1.0]) and _approx(_items(w, b), [0.25, 0.5, 0.75, 1.0]),
		"T12: 堵死状态 10 tick 内稳定（不抖动、不越界）")


func _t13_cross() -> void:
	print("== T13: 侧向并入（方向不一致 → 插入点 0.5）==")
	var w = _new_world()
	_ok(_place(w, "belt", [[2, 6]], [1, 0]) == 0, "T13: 来源格 [2,6] dir(1,0)")
	_ok(_place(w, "belt", [[3, 6]], [0, 1]) == 0, "T13: 目标格 [3,6] dir(0,1)")
	_set_items(w, Vector2i(2, 6), [1.0])
	w.tick(DT)
	_ok(_approx(_items(w, Vector2i(3, 6)), [0.5]),
		"T13: 侧向并入落在 0.5（实际 %s）" % str(_items(w, Vector2i(3, 6))))


func _t14_merge() -> void:
	print("== T14: 合流 round-robin（两来源共用一个落点 0.5）==")
	var w = _new_world()
	var j := Vector2i(3, 6)
	var up := Vector2i(3, 5)
	var down := Vector2i(3, 7)
	_ok(_place(w, "belt", [j], [1, 0]) == 0, "T14: 汇入口 [3,6] dir(1,0)")
	_ok(_place(w, "belt", [up], [0, 1]) == 0, "T14: 上源 [3,5] dir(0,1) → 汇入口")
	_ok(_place(w, "belt", [down], [0, -1]) == 0, "T14: 下源 [3,7] dir(0,-1) → 汇入口")
	var seq: Array = []
	var both := false
	for i in 24:
		for cell in [up, down]:
			if _items(w, cell).is_empty():
				_set_items(w, cell, [1.0])
		w.tick(DT)
		var won := ""
		if _items(w, up).is_empty():
			won = "up"
		if _items(w, down).is_empty():
			if won.is_empty():
				won = "down"
			else:
				both = true
		if not won.is_empty():
			seq.append(won)
	_ok(seq.size() >= 4, "T14: 两来源轮流送块（成功 %d 次：%s）" % [seq.size(), str(seq)])
	_ok(not both, "T14: 同一 tick 不超过一个来源插入 0.5 落点（无并发穿透）")
	var alternating := true
	for i in range(1, seq.size()):
		if seq[i] == seq[i - 1]:
			alternating = false
	_ok(alternating, "T14: round-robin 交替（上/下严格交替：%s）" % str(seq))
	_ok(_items(w, j).size() <= 4, "T14: 汇入口每格 ≤ 4 块（实际 %d）" % _items(w, j).size())


func _t15_inject() -> void:
	print("== T15: 矿机本地缓冲 → 相邻带起点注入（≤2 块/秒）==")
	var w = _new_world()
	_grant(w)
	var miner: int = _place_factory_at(w, "miner", Vector2i(4, 3))
	_ok(miner != 0, "T15: 矿机落位 [4,3]（实体 %d）" % miner)
	_ok(_place(w, "belt", [[4, 2]], [0, -1]) == 0, "T15: 输出带 [4,2] dir(0,-1)——起点 0.0 贴矿机")
	var lg = _logi(w)
	lg.add_buffer(miner, 99)
	_ok(lg.buffer_of(miner) == 4, "T15: 本地缓冲容量 4（请求 99，实际 %d）" % lg.buffer_of(miner))
	_ticks(w, 10) # 1.0 秒
	_ok(lg.buffer_of(miner) == 2, "T15: ≤2 块/秒 —— 1.0 秒注入 2 块（缓冲 4→%d）" % lg.buffer_of(miner))
	_ok(_approx(_items(w, Vector2i(4, 2)), [0.0]),
		"T15: 注入点为带起点 0.0（实际 %s）" % str(_items(w, Vector2i(4, 2))))

	# 垂直相邻（既不是起点也不是终点的对接方向）→ 不注入
	var w2 = _new_world()
	_grant(w2)
	var m2: int = _place_factory_at(w2, "miner", Vector2i(4, 3))
	_ok(_place(w2, "belt", [[4, 2]], [1, 0]) == 0, "T15: 垂直带 [4,2] dir(1,0)")
	var lg2 = _logi(w2)
	lg2.add_buffer(m2, 2)
	_ticks(w2, 10)
	_ok(lg2.buffer_of(m2) == 2 and _items(w2, Vector2i(4, 2)).is_empty(),
		"T15: 垂直相邻的带不接收注入（缓冲仍 %d）" % lg2.buffer_of(m2))

	# 「指向矿机」形态（带终点 1.0 贴矿机）：设计裁定禁止——矿机出料正典只有「带背向矿机」。
	# 若在此注入，矿走完 0.5 秒正好回到矿机格 → deliver_ore(矿机自己)，构成自馈回路。
	# 故断言不注入、且观察 ≥10 tick（最早回送发生在注入后 tick5，只跑 6 tick 看不见）。
	var w3 = _new_world()
	_grant(w3)
	var m3: int = _place_factory_at(w3, "miner", Vector2i(4, 3))
	_ok(_place(w3, "belt", [[4, 4]], [0, -1]) == 0, "T15: 指向矿机的带 [4,4] dir(0,-1)")
	var lg3 = _logi(w3)
	lg3.add_buffer(m3, 2)
	_ticks(w3, 12) # 1.2 秒 = 2.4 个注入周期，覆盖完整往返
	_ok(lg3.buffer_of(m3) == 2, "T15: 指向矿机的带不注入（缓冲仍 %d）" % lg3.buffer_of(m3))
	_ok(_items(w3, Vector2i(4, 4)).is_empty(),
		"T15: 12 tick 无自馈——指向矿机的带始终为空（实际 %s）" % str(_items(w3, Vector2i(4, 4))))
	_ok(_deliveries.is_empty(), "T15: 不产生「矿机把矿送给自己」的交付（实际 %s）" % str(_deliveries))


func _t16_deliver() -> void:
	print("== T16: 端头对接建筑 → world.deliver_ore（任务 5 分流）==")
	# 装配台（配方带矿堆进料）接收矿 → 本地库存；炮塔填弹药是任务 6，其余建筑拒收
	#（拒收 = 返回 false，块留在端头等待，不消失）。
	var w = _new_world()
	_grant(w)
	var asm: int = _place_factory_at(w, "assembler", Vector2i(3, 6))
	_ok(asm != 0, "T16: 装配台落位 [3,6]（实体 %d）" % asm)
	_ok(_place(w, "belt", [[2, 6]], [1, 0]) == 0, "T16: 端头带 [2,6] dir(1,0) 指向建筑")
	_set_items(w, Vector2i(2, 6), [1.0])
	w.tick(DT)
	_ok(_deliveries.size() == 1 and int(_deliveries[0]) == asm,
		"T16: 对接装配台交付一次且携带实体 id（实际 %s）" % str(_deliveries))
	_ok(_items(w, Vector2i(2, 6)).is_empty(), "T16: 交付后块从端头移除")
	var stock = w.get_component(asm, &"ResourceBuffer")
	_ok(stock.count_of(&"ore") == 1, "T16: 矿进装配台本地库存（实际 %d）" % stock.count_of(&"ore"))
	_ok(w.deliver_ore(asm), "T16: world.deliver_ore(装配台) 返回 true")

	# 不接收矿的建筑（发电机：无 Attack、配方无矿堆进料）→ 交付失败，块滞留端头
	var w2 = _new_world()
	var gen: int = _place_factory_at(w2, "generator", Vector2i(3, 6))
	_ok(gen != 0, "T16: 发电机落位 [3,6]")
	_ok(_place(w2, "belt", [[2, 6]], [1, 0]) == 0, "T16: 发电机端头带")
	_set_items(w2, Vector2i(2, 6), [1.0])
	w2.tick(DT)
	_ok(_deliveries.is_empty(), "T16: 发电机不接收矿 → 不发 ore_delivered（实际 %s）" % str(_deliveries))
	_ok(_items(w2, Vector2i(2, 6)).size() == 1, "T16: 交付失败 → 块留在端头等待（不消失）")
	_ok(not w2.deliver_ore(gen), "T16: world.deliver_ore(发电机) 返回 false")


func _t17_inject_rate() -> void:
	print("== T17: 注入节拍无 dt 残留——堵转疏通后速率仍 ≤2 块/秒 ==")
	var w = _new_world()
	_grant(w)
	var miner: int = _place_factory_at(w, "miner", Vector2i(4, 3))
	# 隔离生产端：否则矿机自己的产出会补缓冲，「缓冲仍 4」不再只反映注入（T3-9）
	_freeze_production(w, miner)
	var belt := Vector2i(4, 2)
	_ok(_place(w, "belt", [belt], [0, -1]) == 0, "T17: 输出带 [4,2] dir(0,-1)——起点 0.0 贴矿机")
	var lg = _logi(w)
	lg.add_buffer(miner, 4)
	# 堵转：下游堵塞 → 注入落点被 4 块塞满（容量满），每次注入都失败，节拍被钉在等待重试。
	# 缓冲只在循环外一次性填满：若每个 tick 都回填 4 块，「缓冲仍 4」恒真，注入速率回归
	# 就永远不会红（T3-9）。
	for i in 6:
		_set_items(w, belt, [0.0, 0.25, 0.5, 0.75])
		w.tick(DT)
	_ok(lg.buffer_of(miner) == 4, "T17: 堵转 6 tick 一块未注入（缓冲仍 %d）" % lg.buffer_of(miner))
	# 疏通：清空落点，注入立即恢复；记录每次成功注入所在的 tick
	_set_items(w, belt, [])
	var inject_ticks: Array = []
	var ticks: int = 21
	for i in ticks:
		lg.add_buffer(miner, 4) # 模拟生产端持续供矿，绑定缓冲不干扰节拍
		w.tick(DT)
		var items := _items(w, belt)
		if not items.is_empty() and float(items[0]) < 0.001:
			inject_ticks.append(i + 1)
	print("    T17: 疏通后注入发生在 tick %s（dt=%.2f）" % [str(inject_ticks), DT])
	_ok(inject_ticks.size() >= 4, "T17: 疏通后注入持续恢复（%d 次）" % inject_ticks.size())
	# 首因保护：注入次数不足时上面已报出失败，此处的首末下标计算会越界二次崩、
	# 用 SCRIPT ERROR 盖掉首个失败原因（T3-11）⇒ 直接早退。
	if inject_ticks.size() < 2:
		return
	# 最小间隔：节拍残留 dt 会让相邻两次注入只隔 0.4s（4 tick）
	var min_gap: float = 999.0
	for i in range(1, inject_ticks.size()):
		min_gap = minf(min_gap, float(int(inject_ticks[i]) - int(inject_ticks[i - 1])) * DT)
	_ok(min_gap >= 0.5 - 0.001, "T17: 相邻两次注入间隔 ≥ 0.5s（实测最小 %.2fs）" % min_gap)
	# 平均速率：总块数 / 总时间（首末注入之间）
	var span: float = float(int(inject_ticks[inject_ticks.size() - 1]) - int(inject_ticks[0])) * DT
	var rate: float = float(inject_ticks.size() - 1) / span
	_ok(rate <= 2.0 + 0.001,
		"T17: 平均速率 ≤2 块/秒（%d 块 / %.2fs = %.3f 块/秒）" % [inject_ticks.size() - 1, span, rate])


# ================================================================ 任务 4：管道水网与供水

## 供水真值表查询（world.is_watered = 任务 6 的消费入口）。
func _w(world, id: int) -> bool:
	return world.is_watered(id)


func _t18_water_supply() -> void:
	print("== T18: 连通供水（泵→管→建筑）==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var turret: int = _place_factory_at(w, "gun_turret", Vector2i(6, 2))
	var asm: int = _place_factory_at(w, "assembler", Vector2i(8, 3))
	var gen: int = _place_factory_at(w, "generator", Vector2i(2, 8))
	_ok(pump != 0 and turret != 0 and asm != 0 and gen != 0, "T18: 泵/炮塔/装配台/发电机落位")
	# 管 [5,3] 指向泵（受料端语义 = 泵的对接口）；[6,3] 指向炮塔 [6,2]；[7,3] 指向装配台 [8,3]。
	_ok(_place(w, "pipe", [[5, 3]], [-1, 0]) == 0, "T18: 泵侧管 [5,3] dir(-1,0) 指向泵")
	_ok(_place(w, "pipe", [[6, 3]], [0, -1]) == 0, "T18: 中段管 [6,3] dir(0,-1) 指向炮塔")
	_ok(_place(w, "pipe", [[7, 3]], [1, 0]) == 0, "T18: 末端管 [7,3] dir(1,0) 指向装配台")
	_ok(lg.pump_connected(pump), "T18: 泵判定为有对接管")
	_ok(_w(w, turret), "T18: 炮塔（无 Production）接入管网 → 有水")
	_ok(_w(w, asm), "T18: 装配台接入管网 → 有水")
	_ok(not _w(w, gen), "T18: 远离管网的发电机 → 无水")
	_remove(w, [[7, 3]])
	_ok(_w(w, turret) and not _w(w, asm), "T18: 拆末端管后炮塔仍有水、装配台断水（同网分段）")


func _t19_water_break() -> void:
	print("== T19: 断链停供（每 tick 重算，无脏标记）==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var asm: int = _place_factory_at(w, "assembler", Vector2i(8, 3))
	_ok(lg != null and pump != 0 and asm != 0, "T19: 泵与装配台落位")
	_ok(_place(w, "pipe", [[5, 3]], [-1, 0]) == 0, "T19: 泵侧管 [5,3]")
	_ok(_place(w, "pipe", [[7, 3]], [1, 0]) == 0, "T19: 建筑侧管 [7,3]")
	_ok(not _w(w, asm), "T19: 中间缺 [6,3] → 断链停供")
	_ok(_place(w, "pipe", [[6, 3]], [1, 0]) == 0, "T19: 补上 [6,3] 连通")
	_ok(_w(w, asm), "T19: 连通当帧即恢复供水（每 tick 重算）")
	_ok(_remove(w, [[6, 3]]) == 0, "T19: 拆掉 [6,3]")
	_ok(not _w(w, asm), "T19: 拆除当帧即停供")
	_ok(_remove(w, [[5, 3]]) == 0, "T19: 再拆泵侧管")
	_ok(not lg.pump_connected(pump), "T19: 泵失去对接管")


func _t20_water_multi_pump() -> void:
	print("== T20: 多泵同网（任一泵在网即供水）==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump_a: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var pump_b: int = _place_factory_at(w, "pump", Vector2i(4, 5))
	var asm: int = _place_factory_at(w, "assembler", Vector2i(4, 4))
	_ok(pump_a != 0 and pump_b != 0 and asm != 0, "T20: 两台泵 + 装配台落位")
	_ok(_place(w, "pipe", [[5, 3], [5, 4], [5, 5]], [-1, 0]) == 0,
		"T20: 一条竖管链 [5,3..5,5] dir(-1,0)（两端分别指向两台泵）")
	_ok(lg.pump_connected(pump_a) and lg.pump_connected(pump_b), "T20: 两泵都判定为有对接管")
	_ok(_w(w, asm), "T20: 装配台（管 [5,4] 指向它）有水")
	_ok(_remove(w, [[5, 3]]) == 0, "T20: 拆掉 A 泵的对接管")
	_ok(not lg.pump_connected(pump_a) and lg.pump_connected(pump_b), "T20: A 泵脱网、B 泵仍在网")
	_ok(_w(w, asm), "T20: 剩余泵仍供水（多泵冗余）")
	_ok(_remove(w, [[5, 5]]) == 0, "T20: 再拆 B 泵的对接管")
	_ok(not _w(w, asm), "T20: 全网无泵 → 停供")


func _t21_water_direction() -> void:
	print("== T21: 泵端不查方向、受料端查方向 ==")
	# (a) 泵侧管背离泵：泵端不看 dir（裁定①）→ 仍算对接口、仍播种 → 建筑有水。
	# 这正是「一条 place_line 把一个 dir 写给整条 cells」的真实拖拽几何（T24 端到端覆盖）。
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var asm: int = _place_factory_at(w, "assembler", Vector2i(8, 3))
	_ok(_place(w, "pipe", [[5, 3], [6, 3], [7, 3]], [1, 0]) == 0,
		"T21: 管链 [5,3..7,3] 全条 dir(1,0)——[5,3] 背向泵，[7,3] 指向建筑")
	_ok(lg.pump_connected(pump), "T21: 背离泵的管仍算泵的对接口（泵端不查 line_dir）")
	_ok(_w(w, asm), "T21: 泵端照常播种 → 建筑有水（不再「无种子 → 全网无水」）")
	# (b) 建筑侧管背离建筑：不供水
	var w2 = _new_world()
	_grant(w2)
	var lg2 = _logi(w2)
	var pump2: int = _place_factory_at(w2, "pump", Vector2i(4, 3))
	var asm2: int = _place_factory_at(w2, "assembler", Vector2i(8, 3))
	_ok(_place(w2, "pipe", [[5, 3]], [-1, 0]) == 0, "T21: 泵侧管 [5,3] dir(-1,0) 指向泵")
	_ok(_place(w2, "pipe", [[6, 3], [7, 3]], [-1, 0]) == 0,
		"T21: 建筑侧管 [6,3],[7,3] dir(-1,0)——[7,3] 背离建筑 [8,3]")
	_ok(lg2.pump_connected(pump2), "T21: 泵有对接管（网络已播种）")
	_ok(not _w(w2, asm2), "T21: 相邻管在扩散集合内但方向背离建筑 → 无水")
	# (c) 泵无电：不播种
	var w3 = _new_world()
	_grant(w3)
	w3.state.resources[&"power"] = 0 # 有电才是种子：清空电力池
	var lg3 = _logi(w3)
	var pump3: int = _place_factory_at(w3, "pump", Vector2i(4, 3))
	var asm3: int = _place_factory_at(w3, "assembler", Vector2i(8, 3))
	_ok(pump3 != 0 and asm3 != 0, "T21: 零电力世界的泵/装配台落位")
	_ok(_place(w3, "pipe", [[5, 3]], [-1, 0]) == 0, "T21: 泵侧管 [5,3]")
	_ok(_place(w3, "pipe", [[6, 3], [7, 3]], [1, 0]) == 0, "T21: 通向建筑的管链")
	_ok(lg3.pump_connected(pump3), "T21: 几何上已对接（有管指向泵）")
	_ok(not _w(w3, asm3), "T21: 泵扣不起 1 电 → 不开工 → 不播种（实际 power=%d）"
		% w3.state.get_amount(&"power"))
	w3.state.add(&"power", 200)
	w3.tick(DT)
	_ok(_w(w3, asm3), "T21: 补电后当帧开始供水")


func _t22_pump_drain() -> void:
	print("== T22: 泵缓冲排水（有对接 1 水/秒；无对接积到 4 停产）==")
	# (a) 有对接：1 水/秒排空
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	_freeze_production(w, pump) # 只测物流侧排水，隔离生产端补水
	_ok(_place(w, "pipe", [[5, 3]], [-1, 0]) == 0, "T22: 泵对接管 [5,3] dir(-1,0)")
	lg.add_buffer(pump, 99)
	_ok(lg.buffer_of(pump) == 4, "T22: 缓冲上限 4（实际 %d）" % lg.buffer_of(pump))
	_ticks(w, 10) # 1.0 秒
	_ok(lg.buffer_of(pump) == 3, "T22: 1.0 秒排 1 水（4→%d）" % lg.buffer_of(pump))
	_ticks(w, 10) # 再 1.0 秒
	_ok(lg.buffer_of(pump) == 2, "T22: 2.0 秒排 2 水（4→%d）" % lg.buffer_of(pump))
	_ticks(w, 20) # 排空
	_ok(lg.buffer_of(pump) == 0, "T22: 排空到 0 后不再扣（%d）" % lg.buffer_of(pump))
	_ok(not lg.buffer_full(pump), "T22: 排空后缓冲未满 → 生产端可继续开工")

	# (b) 无对接：只进不出，积到 4 停产
	var w2 = _new_world()
	_grant(w2)
	var lg2 = _logi(w2)
	var pump2: int = _place_factory_at(w2, "pump", Vector2i(4, 3))
	_ok(not lg2.pump_connected(pump2), "T22: 孤立泵无对接管")
	lg2.add_buffer(pump2, 99)
	_ticks(w2, 30)
	_ok(lg2.buffer_of(pump2) == 4, "T22: 无对接 3 秒仍积在 4（实际 %d）" % lg2.buffer_of(pump2))
	_ok(lg2.buffer_full(pump2), "T22: 缓冲满 → buffer_full（任务 5 停产判据）")

	# (c) 背对泵的管：泵端不看方向 → 仍算对接，照常排水
	var w3 = _new_world()
	_grant(w3)
	var lg3 = _logi(w3)
	var pump3: int = _place_factory_at(w3, "pump", Vector2i(4, 3))
	_freeze_production(w3, pump3) # 只测物流侧排水，隔离生产端补水
	_ok(_place(w3, "pipe", [[5, 3]], [1, 0]) == 0, "T22: 背离泵的管 [5,3] dir(1,0)")
	_ok(lg3.pump_connected(pump3), "T22: 背离泵的管也判为有对接管（泵端不查方向）")
	lg3.add_buffer(pump3, 99)
	_ticks(w3, 20) # 2.0 秒 = 2 个排水周期
	_ok(lg3.buffer_of(pump3) == 2, "T22: 方向背对也排水（2.0 秒 4→%d）" % lg3.buffer_of(pump3))


func _t23_water_truth_table() -> void:
	print("== T23: is_watered 真值表（嗜水判定输入）==")
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var gen: int = _place_factory_at(w, "generator", Vector2i(2, 8))
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var turret: int = _place_factory_at(w, "gun_turret", Vector2i(6, 2))
	_ok(not _w(w, gen) and not _w(w, turret), "T23: 无管网时全部 false")
	_ok(not _w(w, 9999), "T23: 未知/不存在的实体 id → false（不报错）")
	var map: Dictionary = lg.watered_map()
	_ok(map.has(gen) and not bool(map[gen]), "T23: 真值表为 Dictionary[int,bool]，未供水实体显式记 false")
	_ok(map.has(turret) and map.has(pump), "T23: 每个在场工厂（含无 Production 的炮塔）都在真值表中")
	_ok(map.size() == w.query(&"Factory").size(), "T23: 真值表条目数 == 在场工厂数（%d / %d）"
		% [map.size(), w.query(&"Factory").size()])
	_place(w, "pipe", [[5, 3]], [-1, 0])
	_place(w, "pipe", [[6, 3]], [0, -1])
	_ok(_w(w, turret) and bool(lg.watered_map()[turret]), "T23: 接通后炮塔真值翻 true")
	_ok(not _w(w, gen), "T23: 未接入的发电机仍 false")
	# 嗜水基因字段可读（任务 6 消费：hydro_thirsty 无水停摆 / hydro_love 有水加速）
	var prod = w.get_component(turret, &"Attack")
	_ok(prod != null and prod.hydro == &"hydro_love", "T23: 炮塔 hydro 字段为 hydro_love（任务 6 输入）")
	_ok(w.get_component(pump, &"Production").hydro == &"hydro_none", "T23: 泵 hydro 字段为 hydro_none")


func _t24_drag_end_to_end() -> void:
	print("== T24: 一条 place_line 直拖（泵→炮塔，全条同 dir）端到端 ==")
	# 玩家可见形态（K1 回归）：从泵格往炮塔方向拖一条直管，CommandSystem 的 _place_line
	# 把**同一个 dir 写给整条 cells**。修复前贴泵段背向泵 → 不播种、不排水：
	# 全网无水（炮塔 is_watered 恒 false）+ 泵缓冲永久卡 4（任务 5 接线后永久停产）。
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var turret: int = _place_factory_at(w, "gun_turret", Vector2i(8, 3))
	_freeze_production(w, pump) # 只测排水与供水，隔离生产端补水
	_ok(pump != 0 and turret != 0, "T24: 泵 [4,3] 与炮塔 [8,3] 落位")
	_ok(_place(w, "pipe", [[5, 3], [6, 3], [7, 3]], [1, 0]) == 0,
		"T24: 一条拖拽指令写三格、全条 dir(1,0)（= 真实拖拽，贴泵段 [5,3] 背向泵）")
	_ok(lg.pump_connected(pump), "T24: 贴泵段背向泵仍算对接（泵端不查方向）")
	_ok(_w(w, turret), "T24: 炮塔 is_watered=true —— 直拖即可供水（K1 的玩家可见形态）")
	lg.add_buffer(pump, 99)
	_ok(lg.buffer_of(pump) == 4, "T24: 泵缓冲置满 4（实际 %d）" % lg.buffer_of(pump))
	_ticks(w, 20) # 2.0 秒 = 2 个排水周期
	_ok(lg.buffer_of(pump) == 2, "T24: 直拖后泵在排水（2.0 秒 4→%d）" % lg.buffer_of(pump))
	_ok(not lg.buffer_full(pump), "T24: 缓冲未满 → 任务 5「无对接停产」判据不会误判")
	_ticks(w, 30) # 排水到底
	_ok(lg.buffer_of(pump) == 0 and _w(w, turret),
		"T24: 排空后管网仍供水（缓冲 %d，炮塔有水=%s）" % [lg.buffer_of(pump), str(_w(w, turret))])
	# 拆掉贴泵段 → 断链：泵失对接、炮塔断水（同一条指令几何下的反向验证）
	_ok(_remove(w, [[5, 3]]) == 0, "T24: 拆掉贴泵段 [5,3]")
	_ok(not lg.pump_connected(pump) and not _w(w, turret), "T24: 拆泵侧管 → 泵脱网且炮塔断水")


# ================================================================ 任务 7：拖拽画线与渲染数据

## 拖拽格集 → 指令 cells 原文形态 [[x, y]...]（协议规定形态，UI 直接抛这个）。
func _protocol(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append([c.x, c.y])
	return out


func _cells_eq(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if got[i] != want[i]:
			return false
	return true


func _t25_drag_to_cells() -> void:
	print("== T25: 拖拽画线 → place_line/remove_line → 格子状态（端到端）==")
	var w = _new_world()
	# ① 纯几何：起点格 + 终点格 → 单轴直链 + 单一 dir（协议只给整条 cells 写一个 dir）
	var a := Vector2i(2, 5)
	var b := Vector2i(4, 5)
	_ok(_cells_eq(LineToolScript.line_cells(a, b), [Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]),
		"T25: 水平拖 2,5→4,5 → 三格直链（实际 %s）" % str(LineToolScript.line_cells(a, b)))
	_ok(LineToolScript.line_dir(a, b) == Vector2i(1, 0), "T25: 向右拖 → dir (1,0)")
	_ok(_cells_eq(LineToolScript.line_cells(b, a), [Vector2i(4, 5), Vector2i(3, 5), Vector2i(2, 5)]),
		"T25: 反向拖的格序与拖拽方向一致")
	_ok(LineToolScript.line_dir(b, a) == Vector2i(-1, 0),
		"T25: 反向拖 4,5→2,5 → dir (-1,0)（R3：箭头方向必须跟随拖拽，玩家靠它自查受料端）")
	_ok(_cells_eq(LineToolScript.line_cells(Vector2i(3, 5), Vector2i(3, 7)),
		[Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7)]), "T25: 垂直拖 → 三格竖链")
	_ok(LineToolScript.line_dir(Vector2i(3, 5), Vector2i(3, 7)) == Vector2i(0, 1), "T25: 向下拖 → dir (0,1)")
	_ok(_cells_eq(LineToolScript.line_cells(Vector2i(2, 5), Vector2i(4, 7)),
		[Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]),
		"T25: 斜拖取主轴（|dx| ≥ |dy| 走 x），不改道")
	_ok(LineToolScript.line_cells(Vector2i(2, 5), Vector2i(2, 5)).size() == 1, "T25: 原地点击 → 单格")
	_ok(LineToolScript.line_dir(Vector2i(2, 5), Vector2i(2, 5)) == Vector2i.ZERO,
		"T25: 原地点击无方向（ZERO，方向回退由 UI 决定）")
	# 单格朝向：像素相对位移判向（同格按下+拖拽 → 主轴方向）
	var pc := Vector2(100, 100)
	_ok(LineToolScript.pixel_dir(pc, pc + Vector2(20, 3)) == Vector2i(1, 0), "T25: 同格右拖 → dir (1,0)")
	_ok(LineToolScript.pixel_dir(pc, pc + Vector2(-20, 3)) == Vector2i(-1, 0), "T25: 同格左拖 → dir (-1,0)")
	_ok(LineToolScript.pixel_dir(pc, pc + Vector2(3, -20)) == Vector2i(0, -1), "T25: 同格上拖 → dir (0,-1)")
	_ok(LineToolScript.pixel_dir(pc, pc + Vector2(2, 20)) == Vector2i(0, 1), "T25: 同格下拖 → dir (0,1)")
	_ok(LineToolScript.pixel_dir(pc, pc + Vector2(1, 1)) == Vector2i.ZERO,
		"T25: 位移 < deadzone（纯点击/手抖）→ ZERO（回退上次方向）")
	_ok(LineToolScript.pixel_dir(pc, pc) == Vector2i.ZERO, "T25: 零位移 → ZERO")
	# 矩形框选作用域：单击退化为单格；反向斜拖两角围出矩形
	var box1: Array[Vector2i] = LineToolScript.rect_cells(Vector2i(2, 5), Vector2i(2, 5))
	_ok(_cells_eq(box1, [Vector2i(2, 5)]), "T25: rect_cells 单击 → 单格（实际 %s）" % str(box1))
	var box2: Array[Vector2i] = LineToolScript.rect_cells(Vector2i(4, 6), Vector2i(2, 5))
	_ok(box2.size() == 6 and box2.has(Vector2i(2, 5)) and box2.has(Vector2i(4, 6)),
		"T25: rect_cells 反向斜拖 → 3x2 矩形 6 格（实际 %s）" % str(box2))

	# ② 指令层落地：拖拽产物按协议原文形态入队
	var cells: Array = LineToolScript.line_cells(a, b)
	var dir: Vector2i = LineToolScript.line_dir(a, b)
	_ok(_place(w, "pipe", _protocol(cells), [dir.x, dir.y]) == 0, "T25: 拖拽格集直接作为 place_line cells 被接受")
	var all_ok := true
	for c in cells:
		var cell = w.grid.get_cell(c)
		if cell.line_kind != &"pipe" or cell.line_dir != dir:
			all_ok = false
	_ok(all_ok, "T25: 三格 line_kind=pipe 且 line_dir 跟随拖拽方向")
	_ok(_line_events.size() == 3, "T25: 每格一条 line_changed（实际 %d）" % _line_events.size())

	# ③ 拆除拖拽：反向拖回同一行 → 整条拆掉
	var rm: Array = LineToolScript.line_cells(b, a)
	w.push_command({"type": "remove_line", "cells": _protocol(rm)})
	w.tick(DT)
	_ok(w.grid.get_cell(Vector2i(2, 5)).line_kind == &"" and w.grid.get_cell(Vector2i(4, 5)).line_kind == &"",
		"T25: 拖拽拆除清空整条（含反向拖的格序）")

	# ④ 拒绝路径：拖过路径格（非 buildable）→ 整条不动、只发一次拒绝
	var bad: Array = LineToolScript.line_cells(Vector2i(1, 1), Vector2i(3, 1))
	var before: int = _rejects.size()
	w.push_command({"type": "place_line", "kind": "belt", "cells": _protocol(bad), "dir": [1, 0]})
	w.tick(DT)
	var untouched := true
	for c in bad:
		if c != Vector2i(1, 1) and w.grid.get_cell(c).line_kind != &"":
			untouched = false
	_ok(_rejects.size() == before + 1 and untouched, "T25: 拖过路径格 → 整条拒绝且其余格未写入")


func _t26_render_data() -> void:
	print("== T26: 渲染数据读取（logistics_layer 只读快照 + 矿块屏幕坐标）==")
	var w = _new_world()
	_place(w, "pipe", [[2, 5], [3, 5]], [1, 0])
	_place(w, "belt", [[4, 6]], [0, 1])
	var items: Array = LogisticsLayerScript.line_items(w)
	_ok(items.size() == 3, "T26: 只暴露有线格（3 条线，实际 %d）" % items.size())
	var belt_item: Dictionary = {}
	var pipe_cells: Array = []
	for it in items:
		if str(it["kind"]) == "belt":
			belt_item = it
		elif str(it["kind"]) == "pipe":
			pipe_cells.append(it["cell"])
	_ok(not belt_item.is_empty() and belt_item["dir"] == Vector2i(0, 1),
		"T26: belt 条目携带 line_dir（实际 %s）" % str(belt_item.get("dir")))
	_ok(_cells_eq(pipe_cells, [Vector2i(2, 5), Vector2i(3, 5)]), "T26: pipe 格集正确（升序）")
	_ok(belt_item.get("items") is Array and (belt_item["items"] as Array).is_empty(),
		"T26: 空带 items 为空数组")
	# 矿块屏幕坐标：入口 = 格心 - dir*半格，t 沿 dir 前进
	var cs := 64.0
	_ok(LogisticsLayerScript.ore_pos(Vector2i(2, 5), Vector2i(1, 0), 0.0, cs) == Vector2(2 * cs, 5 * cs + cs * 0.5),
		"T26: dir(1,0) t=0 → 本格左边中点")
	_ok(LogisticsLayerScript.ore_pos(Vector2i(2, 5), Vector2i(1, 0), 0.5, cs) == Vector2(2 * cs + cs * 0.5, 5 * cs + cs * 0.5),
		"T26: dir(1,0) t=0.5 → 格心")
	_ok(LogisticsLayerScript.ore_pos(Vector2i(2, 5), Vector2i(0, -1), 1.0, cs) == Vector2(2 * cs + cs * 0.5, 5 * cs),
		"T26: dir(0,-1) t=1 → 本格上边中点（入口在底边）")
	# 块位由逻辑层推进，渲染只读不写
	var bc = w.grid.get_cell(Vector2i(4, 6))
	bc.belt_items.append(0.75)
	items = LogisticsLayerScript.line_items(w)
	var got: Array = []
	for it in items:
		if str(it["kind"]) == "belt":
			got = it["items"]
	_ok(_approx(got, [0.75]), "T26: items 跟随 belt_items（实际 %s）" % str(got))
	_ok(is_equal_approx(bc.belt_items[0], 0.75) and bc.belt_items.size() == 1,
		"T26: 快照只读——读渲染数据不改世界")
	# 拆线后从快照消失
	_remove(w, [[4, 6]])
	_ok(LogisticsLayerScript.line_items(w).size() == 2, "T26: 拆线后该格不再进渲染快照")

# ================================================================ T27 产品裁定轮（三处无声失败 + 拆除过滤）

## 裁定 ①：断水提示（边沿 + 原因分档）——「有水 → 无水」才发，且只有「没有任何相邻管
## 指向本格」时才说「管道方向需指向建筑」；断电 / 上游拆管走中性档（NEW-3）。
## 场景：泵 [2,5] → 管 [3,5][4,5] dir(1,0) → 建筑 [5,5]（接水）。
func _t27_water_hint() -> void:
	print("== T27a: 断水提示（water_lost 边沿 + 原因分档，同因只提示一次）==")
	var w = _new_world()
	_grant(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(2, 5))
	var bld: int = _place_factory_at(w, "generator", Vector2i(5, 5))
	_ok(pump != 0 and bld != 0, "T27a: 水泵 [2,5] / 建筑 [5,5] 落位")
	_freeze_production(w, bld) # 建筑自身不产电（避免断电用例被自补电救活）
	var hints: Array = [] # [eid, reason]
	w.water_lost.connect(func(eid, reason): hints.append([int(eid), str(reason)]))
	_ok(_place(w, "pipe", [[3, 5], [4, 5]], [1, 0]) == 0, "T27a: 铺管 [3,5][4,5] dir(1,0)（指向建筑）")
	_ok(w.is_watered(bld), "T27a: 前置：建筑已接水")
	_ok(hints.is_empty(), "T27a: 供水正常时不发断水提示（实际 %d）" % hints.size())
	# —— 场景 1：方向错（同帧拆+重铺背离方向）→ 定向提示
	w.push_command({"type": "remove_line", "cells": [[4, 5]]})
	w.push_command({"type": "place_line", "kind": "pipe", "cells": [[4, 5]], "dir": [0, 1]})
	w.tick(DT)
	_ok(not w.is_watered(bld), "T27a: 管道方向背离 → 断水")
	_ok(hints.size() == 1 and int(hints[0][0]) == bld and str(hints[0][1]) == World.WATER_LOST_DIRECTION,
		"T27a: 方向背离 → 发 1 次 water_lost(建筑, direction)（实际 %s）" % str(hints))
	_ok(World.water_hint_text(World.WATER_LOST_DIRECTION) == "管道方向需指向建筑",
		"T27a: direction 档文案点名方向（实际 %s）" % World.water_hint_text(World.WATER_LOST_DIRECTION))
	_ticks(w, 10)
	_ok(hints.size() == 1, "T27a: 同一断水态连跑 10 tick 不重复提示（实际 %d）" % hints.size())
	var pump_hints: int = 0
	for h in hints:
		if int(h[0]) == pump:
			pump_hints += 1
	_ok(pump_hints == 0, "T27a: 泵自身不触发提示（泵端不判方向，提示会误导）")
	# —— 场景 2：复水 → 再断（沿语义仍成立）
	w.push_command({"type": "remove_line", "cells": [[4, 5]]})
	w.push_command({"type": "place_line", "kind": "pipe", "cells": [[4, 5]], "dir": [1, 0]})
	w.tick(DT)
	_ok(w.is_watered(bld), "T27a: 改回指向建筑 → 复水")
	# —— 场景 3：断电 → 中性档，不误导去查方向（NEW-3）
	_power_cut(w, pump)
	w.tick(DT)
	_ok(not w.is_watered(bld), "T27a: 断电 → 断水（管仍指向建筑）")
	_ok(hints.size() == 2 and str(hints[1][1]) == World.WATER_LOST_UNSUPPLIED,
		"T27a: 断电不发 direction 档（实际 %s）" % str(hints))
	if hints.size() == 2:
		var cut_text: String = World.water_hint_text(str(hints[1][1]))
		_ok(cut_text.find("方向") == -1,
			"T27a: 断电回执不点名方向（实际「%s」）" % cut_text)
	# 恢复供电 → 复水 → 不再提示
	w.state.resources[&"power"] = 200
	w.tick(DT)
	_ok(w.is_watered(bld), "T27a: 恢复供电 → 复水")
	_ok(hints.size() == 2, "T27a: 复水本身不提示（实际 %d）" % hints.size())
	# —— 场景 4：上游拆管（贴建筑的管仍指向建筑）→ 中性档；重铺后复水
	w.push_command({"type": "remove_line", "cells": [[3, 5]]})
	w.tick(DT)
	_ok(not w.is_watered(bld), "T27a: 拆上游管 [3,5] → 断水（[4,5] 仍指向建筑）")
	_ok(hints.size() == 3 and str(hints[2][1]) == World.WATER_LOST_UNSUPPLIED,
		"T27a: 上游拆管不发 direction 档（实际 %s）" % str(hints))
	w.push_command({"type": "place_line", "kind": "pipe", "cells": [[3, 5]], "dir": [1, 0]})
	w.tick(DT)
	_ok(w.is_watered(bld) and hints.size() == 3,
		"T27a: 重铺上游管 → 复水且不提示（实际 %d 次）" % hints.size())
	# —— 场景 5：重铺后再把指向管改背离 → 又回到定向档（方向确实是可改的一环）
	w.push_command({"type": "remove_line", "cells": [[4, 5]]})
	w.push_command({"type": "place_line", "kind": "pipe", "cells": [[4, 5]], "dir": [0, -1]})
	w.tick(DT)
	_ok(not w.is_watered(bld) and hints.size() == 4
		and str(hints[3][1]) == World.WATER_LOST_DIRECTION,
		"T27a: 复水后再断（方向背离）→ 再提示 direction（共 %d 次）" % hints.size())
	# 相邻没管（真断源，不是方向问题）→ 不提示
	var w2 = _new_world()
	_grant(w2)
	var bld2: int = _place_factory_at(w2, "generator", Vector2i(5, 5))
	var hints2: Array = []
	w2.water_lost.connect(func(eid, reason): hints2.append([int(eid), str(reason)]))
	_ticks(w2, 3)
	_ok(hints2.is_empty() and not w2.is_watered(bld2), "T27a: 从来没接水的建筑不发提示（无真→假沿）")


## 断电模拟：池里电清零 + 泵当前周期作废（active 会绕过 can_afford，见 _pump_can_run）。
func _power_cut(world, pump_id: int) -> void:
	world.state.resources[&"power"] = 0
	var prod = world.get_component(pump_id, &"Production")
	if prod != null:
		prod.active = false
		prod.progress = 0.0


## T27d（退役）：断水回执去重随战报口径改动一并移除——战报现在只显示
## 「第X波：敌人构成」与「击败了xxx 掉落xxx」两类，game 层不再消费 water_lost。


## 裁定 ②：拆除只拆有线格（接线层过滤）——拖拽扫过的空格不再让整条被拒。
## 指令层仍是严格的「每格必须有线」（内核不动），过滤只发生在 game.cells_with_line。
func _t27_remove_filter() -> void:
	print("== T27b: 拆除只提交有线格（cells_with_line 过滤）==")
	var w = _new_world()
	_ok(_place(w, "pipe", [[6, 6], [7, 6]], [1, 0]) == 0, "T27b: 铺 [6,6][7,6] 两格管")
	var drag: Array = [Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]
	var kept: Array = GameScript.cells_with_line(w, drag)
	_ok(_cells_eq(kept, [Vector2i(6, 6), Vector2i(7, 6)]),
		"T27b: 拖过 4 格（两端空格）→ 只留有线 2 格（实际 %s）" % str(kept))
	_ok(GameScript.cells_with_line(w, [Vector2i(9, 6)]).is_empty(), "T27b: 全是空格 → 过滤结果为空")
	_ok(GameScript.cells_with_line(w, [Vector2i(6, 6), Vector2i(6, 6)]).size() == 1,
		"T27b: 重复格去重（同格只拆一次）")
	# 对照：未经过滤的原始拖拽在指令层被严格拒绝（内核语义不变）
	var before: int = _rejects.size()
	w.push_command({"type": "remove_line", "cells": _protocol(drag)})
	w.tick(DT)
	_ok(_rejects.size() == before + 1 and w.grid.get_cell(Vector2i(6, 6)).line_kind == &"pipe",
		"T27b: 对照——未过滤的拖拽仍整条被拒（%d 次拒绝）" % (_rejects.size() - before))
	# 过滤后提交：成功拆掉两格，无拒绝、无残留
	_rejects.clear()
	w.push_command({"type": "remove_line", "cells": _protocol(GameScript.cells_with_line(w, drag))})
	w.tick(DT)
	_ok(w.grid.get_cell(Vector2i(6, 6)).line_kind == &"" and w.grid.get_cell(Vector2i(7, 6)).line_kind == &"",
		"T27b: 过滤后提交 → 两格线路拆净")
	_ok(_rejects.is_empty(), "T27b: 过滤后提交无拒绝（实际 %d）" % _rejects.size())


## 覆盖放置（原裁定 ③ 拐弯提示随覆盖语义移除）：起手格已有线不再被拒——
## place_line 对已有线格先拆除再放置。这里钉住「拐角格续拖 = 覆盖」与「覆盖清块位」。
func _t27_overwrite() -> void:
	print("== T27c: 覆盖放置（已有线格先拆后放）==")
	var w = _new_world()
	_ok(_place(w, "pipe", [[6, 6]], [1, 0]) == 0, "T27c: 先铺 [6,6] pipe")
	var before: int = _rejects.size()
	# 旧拐弯场景：起手格已有线的续拖，现在 = 覆盖 [6,6] 并延伸 [7,6]
	_ok(_place(w, "belt", [[6, 6], [7, 6]], [1, 0]) == 0, "T27c: 拐角格续拖（覆盖放置）成功")
	_ok(_rejects.size() == before, "T27c: 覆盖放置无拒绝回执（实际 %d）" % (_rejects.size() - before))
	var c66 = w.grid.get_cell(Vector2i(6, 6))
	_ok(c66.line_kind == &"belt" and c66.line_dir == Vector2i(1, 0), "T27c: [6,6] 被覆盖为 belt")
	var c76 = w.grid.get_cell(Vector2i(7, 6))
	_ok(c76.line_kind == &"belt", "T27c: [7,6] 正常写入 belt")
	# 覆盖 = 先拆除：旧 belt 上的块位（belt_items）必须被清空，不残留到新线上
	c66.belt_items.append(0.5)
	_ok(_place(w, "pipe", [[6, 6]], [0, 1]) == 0, "T27c: belt→pipe 覆盖成功")
	_ok(c66.line_kind == &"pipe" and c66.belt_items.is_empty(),
		"T27c: 覆盖后旧块位清空（先拆除再放置，实际 kind=%s items=%d）" % [str(c66.line_kind), c66.belt_items.size()])
	# 其余拒绝原因不受覆盖影响：路径格照旧被拒
	before = _rejects.size()
	w.push_command({"type": "place_line", "kind": "pipe", "cells": [[1, 1]], "dir": [1, 0]})
	w.tick(DT)
	_ok(_rejects.size() == before + 1, "T27c: 路径格仍被拒绝（实际 %s）" % (_rejects[-1] if _rejects.size() > before else "无"))


func _t27_product_rulings() -> void:
	_t27_water_hint()
	_t27_remove_filter()
	_t27_overwrite()


# ================================================================ T28 拐弯拼接（渲染接线几何）

## 逐格画「入口边 → 出口边」会让拐弯处断开：带/管在格边中点相接，
## 而拐角格的上游方向与自身 line_dir 不一致。T28 锁死渲染层的接线判据：
##   ① belt 上游 = 邻居 N 满足 N + N.dir == 本格（与 LogisticsSystem 的 target 同公式）；
##   ② 相邻格在边中点精确重合（edge_point(A,+d) == edge_point(A+d,-d)）；
##   ③ 拐弯格块位 path_pos：t=0 入边中点、0.5 格心（= CROSS_DIR_POS）、1 出口边中点；
##   ④ 管道 links 无向、与 line_dir 无关（L/T/十字都能拼上）。
func _t28_corner_join() -> void:
	print("== T28: 拐弯拼接（渲染接线几何）==")
	var w = _new_world()
	var cs := 64.0
	# 横段 (2,2)→(4,2) dir 右；纵段 (5,2)→(5,4) dir 下 —— (4,2) 的出口正好落进 (5,2)
	_ok(_place(w, "belt", [[2, 2], [3, 2], [4, 2]], [1, 0]) == 0, "T28: 铺横段 3 格带")
	_ok(_place(w, "belt", [[5, 2], [5, 3], [5, 4]], [0, 1]) == 0, "T28: 铺纵段 3 格带")
	var turn := Vector2i(5, 2)
	_ok(_same_dirs(LogisticsLayerScript.in_dirs(w, turn), [Vector2i(-1, 0)]),
		"T28: 拐角格上游 = 左侧（实际 %s）" % str(LogisticsLayerScript.in_dirs(w, turn)))
	_ok(_same_dirs(LogisticsLayerScript.in_dirs(w, Vector2i(3, 2)), [Vector2i(-1, 0)]),
		"T28: 直线中段上游只有左侧（右侧邻格指向别处，不算上游，实际 %s）"
		% str(LogisticsLayerScript.in_dirs(w, Vector2i(3, 2))))
	_ok(LogisticsLayerScript.in_dirs(w, Vector2i(2, 2)).is_empty(), "T28: 起点格 in_dirs 为空")
	# ② 拼接点：前格出口 == 后格入边（同一个世界坐标，视觉无裂缝）
	var a_out: Vector2 = LogisticsLayerScript.edge_point(Vector2i(4, 2), Vector2i(1, 0), cs)
	var b_in: Vector2 = LogisticsLayerScript.edge_point(turn, Vector2i(-1, 0), cs)
	_ok(a_out == b_in, "T28: 前格出口点 == 拐角格左侧入点（%s / %s）" % [str(a_out), str(b_in)])
	# ③ 拐弯块位三点 + 跨格不跳位
	var center: Vector2 = LogisticsLayerScript.edge_point(turn, Vector2i.ZERO, cs)
	_ok(LogisticsLayerScript.path_pos(turn, Vector2i(0, 1), Vector2i(-1, 0), 0.0, cs) == b_in,
		"T28: 拐弯 t=0 → 入边中点")
	_ok(LogisticsLayerScript.path_pos(turn, Vector2i(0, 1), Vector2i(-1, 0), 0.5, cs) == center,
		"T28: 拐弯 t=0.5 → 格心（= CROSS_DIR_POS 落点）")
	_ok(LogisticsLayerScript.path_pos(turn, Vector2i(0, 1), Vector2i(-1, 0), 1.0, cs)
		== LogisticsLayerScript.edge_point(turn, Vector2i(0, 1), cs), "T28: 拐弯 t=1 → 出口边中点")
	var before: Vector2 = LogisticsLayerScript.path_pos(turn, Vector2i(0, 1), Vector2i(-1, 0), 0.49, cs)
	var after: Vector2 = LogisticsLayerScript.path_pos(turn, Vector2i(0, 1), Vector2i(-1, 0), 0.51, cs)
	_ok(before.distance_to(center) < 2.0 and after.distance_to(center) < 2.0,
		"T28: 拐弯处块位连续（拐点两侧都贴着格心）")
	# 直线退化：path_pos(in_dir=-dir) 与 ore_pos 逐字相同（T26 契约不破）
	var same := true
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		if LogisticsLayerScript.path_pos(Vector2i(3, 2), Vector2i(1, 0), Vector2i(-1, 0), float(t), cs) \
			!= LogisticsLayerScript.ore_pos(Vector2i(3, 2), Vector2i(1, 0), float(t), cs):
			same = false
	_ok(same, "T28: 直线格 path_pos == ore_pos（旧契约不变）")
	# ④ 管道：links 双向且与 line_dir 无关（两格都写 dir 右，仍互相连通）
	_ok(_place(w, "pipe", [[8, 5]], [1, 0]) == 0, "T28: 铺管 (8,5) dir 右")
	_ok(_place(w, "pipe", [[8, 6]], [1, 0]) == 0, "T28: 铺管 (8,6) dir 右（方向与邻接无关）")
	_ok(_same_dirs(LogisticsLayerScript.pipe_links(w, Vector2i(8, 5)), [Vector2i(0, 1)]),
		"T28: 上管 links 指向下邻（实际 %s）" % str(LogisticsLayerScript.pipe_links(w, Vector2i(8, 5))))
	_ok(_same_dirs(LogisticsLayerScript.pipe_links(w, Vector2i(8, 6)), [Vector2i(0, -1)]),
		"T28: 下管 links 指向上邻（双向闭合）")
	_ok(LogisticsLayerScript.pipe_links(w, Vector2i(2, 2)).is_empty(),
		"T28: 相邻有带但无管 → 管道不串到传送带上")
	# 孤立管：无 links（渲染画管桩）
	_ok(_place(w, "pipe", [[12, 8]], [1, 0]) == 0, "T28: 铺孤立管")
	_ok(LogisticsLayerScript.pipe_links(w, Vector2i(12, 8)).is_empty(), "T28: 孤立管 links 为空")
	# 快照字段：line_items 携带 in_dirs / links（渲染层唯一入口）
	var snap: Dictionary = {}
	for it in LogisticsLayerScript.line_items(w):
		if it["cell"] == turn:
			snap = it
	_ok(not snap.is_empty() and _same_dirs(snap.get("in_dirs", []), [Vector2i(-1, 0)]),
		"T28: 快照携带拐角格的 in_dirs")
	_ok(_same_dirs(snap.get("links", []), [Vector2i(0, 1), Vector2i(-1, 0)]),
		"T28: 快照 links = 出口 + 上游（实际 %s）" % str(snap.get("links")))
	# 矿块图标与 HUD 资源栏同源：路径写错要立刻红（渲染层靠它画块）
	_ok(Art.tex(str(Art.RES_ICON.get("ore", ""))) != null, "T28: 矿块图标 ore.png 可加载")
	_ok(LogisticsLayerScript.ORE_W_RATIO > 0.0 and LogisticsLayerScript.ORE_W_RATIO < LogisticsLayerScript.BELT_W_RATIO,
		"T28: 矿块图标小于带面宽度（不溢出带边）")


## 方向数组比较（顺序敏感：NEIGHBORS 固定序，渲染确定性依赖它）。
func _same_dirs(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if got[i] != want[i]:
			return false
	return true
