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
	w.command_rejected.connect(func(r): _rejects.append(str(r)))
	w.line_changed.connect(func(c, k): _line_events.append([c, k]))
	return w


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

	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	return _failures
