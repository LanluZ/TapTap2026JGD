extends SceneTree
## 物流数据层与放置/拆除指令 headless 验证（任务 2/8）：
## Cell 的线路字段（line_kind/line_dir/belt_items）→ GridSystem 校验 →
## CommandSystem 的 place_line / remove_line 指令协议 → world.line_changed 信号。
## 运行：godot --headless --path <项目目录> -s res://tests/logistics_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
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
	_ok(_place(w4, "belt", [[6, 6]], [0, 1]) == 1, "已有线路的格重复放置被拒绝")
	_ok(w4.grid.get_cell(Vector2i(6, 6)).line_kind == &"pipe", "拒绝后原 pipe 保持不变")
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
	print("== T16: 端头对接建筑 → world.deliver_ore（stub）==")
	var w = _new_world()
	var gen: int = _place_factory_at(w, "generator", Vector2i(3, 6))
	_ok(gen != 0, "T16: 建筑落位 [3,6]（实体 %d）" % gen)
	_ok(_place(w, "belt", [[2, 6]], [1, 0]) == 0, "T16: 端头带 [2,6] dir(1,0) 指向建筑")
	_set_items(w, Vector2i(2, 6), [1.0])
	w.tick(DT)
	_ok(_deliveries.size() == 1 and int(_deliveries[0]) == gen,
		"T16: 对接建筑交付一次且携带实体 id（实际 %s）" % str(_deliveries))
	_ok(_items(w, Vector2i(2, 6)).is_empty(), "T16: 交付后块从端头移除")
	_ok(w.deliver_ore(gen), "T16: world.deliver_ore(entity_id) 返回 true（任务 6 前的 stub）")


func _t17_inject_rate() -> void:
	print("== T17: 注入节拍无 dt 残留——堵转疏通后速率仍 ≤2 块/秒 ==")
	var w = _new_world()
	_grant(w)
	var miner: int = _place_factory_at(w, "miner", Vector2i(4, 3))
	var belt := Vector2i(4, 2)
	_ok(_place(w, "belt", [belt], [0, -1]) == 0, "T17: 输出带 [4,2] dir(0,-1)——起点 0.0 贴矿机")
	var lg = _logi(w)
	lg.add_buffer(miner, 4)
	# 堵转：下游堵塞 → 注入落点被 4 块塞满（容量满），每次注入都失败，节拍被钉在等待重试
	for i in 6:
		lg.add_buffer(miner, 4)
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
	print("== T21: 方向背对不算对接 ==")
	# (a) 泵侧管背离泵：不播种 → 整网无水
	var w = _new_world()
	_grant(w)
	var lg = _logi(w)
	var pump: int = _place_factory_at(w, "pump", Vector2i(4, 3))
	var asm: int = _place_factory_at(w, "assembler", Vector2i(8, 3))
	_ok(_place(w, "pipe", [[5, 3], [6, 3], [7, 3]], [1, 0]) == 0,
		"T21: 管链 [5,3..7,3] dir(1,0)——[5,3] 背离泵，[7,3] 指向建筑")
	_ok(not lg.pump_connected(pump), "T21: 背离泵的管不算泵的对接口（不播种）")
	_ok(not _w(w, asm), "T21: 无种子 → 建筑无水（纵使末端管指向它）")
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

	# (c) 背对泵的管：不算对接，不排水
	var w3 = _new_world()
	_grant(w3)
	var lg3 = _logi(w3)
	var pump3: int = _place_factory_at(w3, "pump", Vector2i(4, 3))
	_ok(_place(w3, "pipe", [[5, 3]], [1, 0]) == 0, "T22: 背离泵的管 [5,3] dir(1,0)")
	lg3.add_buffer(pump3, 99)
	_ticks(w3, 20)
	_ok(lg3.buffer_of(pump3) == 4, "T22: 方向背对 → 不排水（缓冲仍 %d）" % lg3.buffer_of(pump3))


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

