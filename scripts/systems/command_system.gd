class_name CommandSystem
extends System
## #1 应用玩家指令（§5）。UI 层经 World.push_command 入队，本系统在每逻辑帧
## 最开始消费（§1「下一逻辑帧开始时执行」；CommandQueue 队列体在 World 上）。
##
## 指令协议（键名即协议，UI 层按此写入）：
##   {"type": "play_card",     "card_index": int, "cell": [x, y] 或 Vector2i}
##   {"type": "place_factory", "blueprint_id": String, "cell": [x, y] 或 Vector2i}
##   {"type": "place_tile",    "tile_type": String, "cell": [x, y] 或 Vector2i}
##   {"type": "fuse",          "a": int, "b": int, "seed": int（可选）}  # DNA 融合
##   {"type": "place_line",    "kind": "pipe"|"belt", "cells": [[x, y]...], "dir": [dx, dy]}
##   {"type": "remove_line",   "cells": [[x, y]...]}
## 失败一律发 world.command_rejected(reason)：不改世界、不扣费（已扣则回滚）。

const GenomeScript = preload("res://scripts/dna/genome.gd")

var _grid_system = null
var _card_system = null


func setup(world) -> void:
	_grid_system = world.get_system("GridSystem")
	_card_system = world.get_system("CardSystem")


func tick(world, _dt: float) -> void:
	for cmd in world.drain_commands():
		_apply(world, cmd)


func _apply(world, cmd) -> void:
	if not (cmd is Dictionary):
		_reject(world, "指令不是 Dictionary")
		return
	var d: Dictionary = cmd
	if world.state != null and not world.state.is_playing():
		_reject(world, "游戏已结束（%s），忽略指令 %s" % [world.state.status, str(d.get("type", "?"))])
		return
	match str(d.get("type", "")):
		"play_card":
			_play_card(world, d)
		"place_factory":
			_place_factory(world, str(d.get("blueprint_id", "")), _cell_of(d))
		"place_tile":
			_place_tile(world, str(d.get("tile_type", "")), _cell_of(d))
		"fuse":
			_fuse(world, int(d.get("a", 0)), int(d.get("b", 0)), int(d.get("seed", -1)))
		"place_line":
			_place_line(world, str(d.get("kind", "")), _cells_of(d), _dir_of(d))
		"remove_line":
			_remove_line(world, _cells_of(d))
		_:
			_reject(world, "未知指令类型 '%s'" % str(d.get("type", "")))


## 打出卡牌（§8）：结算放置效果 → 扣卡费 → 手牌移除 → 登记补抽 1 张（CardSystem #10）。
## 例外：融合子代卡（card_fusion_*）打出不补抽——子代卡面唯一，抽回没有意义。
func _play_card(world, d: Dictionary) -> void:
	if _card_system == null:
		_reject(world, "CardSystem 未注册")
		return
	var deck = _card_system.deck
	var idx := int(d.get("card_index", -1))
	if idx < 0 or idx >= deck.hand.size():
		_reject(world, "手牌下标越界: %d（现有 %d 张）" % [idx, deck.hand.size()])
		return
	var card_id: StringName = deck.hand[idx]
	var card: Dictionary = world.config.get_card(card_id)
	if card.is_empty():
		_reject(world, "未定义卡牌: " + String(card_id))
		return
	var cell = _cell_of(d)
	if cell == null:
		_reject(world, "play_card 缺少合法 cell")
		return
	var cost: Dictionary = card["cost"]
	if not world.state.can_afford(cost):
		_reject(world, "打出 %s 资源不足" % String(card_id))
		return
	if not world.state.pay(cost):
		_reject(world, "扣费失败（内部错误）: " + String(card_id))
		return
	var eff: Dictionary = card["effect"]
	var ok := false
	match str(eff.get("type", "")):
		"place_factory":
			ok = _place_factory(world, str(eff.get("blueprint_id", "")), cell)
		"place_tile":
			ok = _place_tile(world, str(eff.get("tile_type", "")), cell)
		_:
			_reject(world, "卡牌 %s 效果类型未知" % String(card_id))
	if not ok:
		world.state.refund(cost) # 放置失败回滚卡费
		return
	deck.hand.remove_at(idx)
	if not String(card_id).begins_with("card_fusion_"):
		deck.pending_draw += 1 # 0 消耗规则：打出自动抽 1（§12），CardSystem #10 执行


## 放置工厂：蓝图校验 → 占用校验（GridSystem）→ 扣蓝图 cost → 按蓝图组件组合创建实体。
func _place_factory(world, blueprint_id: String, cell) -> bool:
	var bp: Dictionary = world.config.get_blueprint(StringName(blueprint_id))
	if bp.is_empty():
		_reject(world, "未定义蓝图: " + blueprint_id)
		return false
	if cell == null:
		_reject(world, "place_factory 缺少合法 cell")
		return false
	if _grid_system == null or not _grid_system.can_build(world, cell):
		_reject(world, "格子不可建造: %s" % str(cell))
		return false
	var cost: Dictionary = bp["cost"]
	if not world.state.pay(cost):
		_reject(world, "放置 %s 资源不足" % blueprint_id)
		return false
	var id: int = world.create_entity()
	var display_name := GenomeScript.phenotype_name(bp["genome"], world.config.genes) # 表型命名（策划案 15.6）
	var specs: Array = GenomeScript.express(bp["genome"], world.config.genes, blueprint_id, display_name)
	for spec in specs:
		var sd: Dictionary = spec
		var comp = GameConfig.make_component(str(sd.get("type", "")), sd)
		if comp == null:
			world.state.refund(cost)
			world.destroy_entity(id)
			_reject(world, "蓝图 %s 组件创建失败: %s" % [blueprint_id, str(sd.get("type", ""))])
			return false
		if comp is GridPosition:
			comp.cell = cell
		world.add_component(id, comp)
	world.grid.occupy(cell, id)
	return true


## DNA 融合（规格 2026-10-13-dna-fusion-design §4）：双亲减数分裂 → 子代卡入手。
## 无消耗无冷却，代价是双亲实体销毁、格子由 GridSystem 清扫释放。
func _fuse(world, a: int, b: int, seed: int) -> void:
	if a == b:
		_reject(world, "融合需要两个不同的工厂（当前都是实体 %d）" % a)
		return
	var parents: Array = []
	for eid in [a, b]:
		if not world.is_alive(eid) or not world.has_component(eid, &"Factory"):
			_reject(world, "实体 %d 不是在场工厂，无法融合" % eid)
			return
		parents.append(world.get_component(eid, &"Factory"))
	if _card_system == null:
		_reject(world, "CardSystem 未注册")
		return
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
		world.state.fusion_seed = seed
	else:
		rng.seed = world.state.fusion_seed if world.state.fusion_seed != 0 else randi()
	var child_genome: Array = GenomeScript.breed(parents[0].genome, parents[1].genome, world.config.genes, rng)
	var child_name := GenomeScript.phenotype_name(child_genome, world.config.genes)
	var child_card: StringName = GenomeScript.register_child(world.config, child_genome, child_name)
	world.destroy_entity(a)
	world.destroy_entity(b)
	_card_system.receive_card(child_card)


## 放置地块（§7）：地块不是实体，写入 GridMapData.cells[cell].tile_type（§4）。
func _place_tile(world, tile_type: String, cell) -> bool:
	var level: Dictionary = world.config.get_level(world.state.level_id)
	var tile_types: Dictionary = level.get("tile_types", {})
	if not tile_types.has(StringName(tile_type)):
		_reject(world, "未定义地块类型: " + tile_type)
		return false
	if cell == null:
		_reject(world, "place_tile 缺少合法 cell")
		return false
	if _grid_system == null or not _grid_system.can_place_tile(world, cell):
		_reject(world, "格子已被占用或不是路面，无法放地块: %s" % str(cell))
		return false
	var placed := StringName(tile_type)
	world.grid.set_tile(cell, placed)
	# 邻接合成（§19.2 Loop Hero 式确定性变换）：与同种地块相邻时，后放的这块变为 combine 目标
	var target: StringName = (tile_types.get(placed, {}) as Dictionary).get("combine", &"")
	if not target.is_empty():
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = world.grid.get_cell(cell + off)
			if n != null and n.tile_type == placed:
				world.grid.set_tile(cell, target)
				break
	return true


## 放置线路（管道/传送带）：GridSystem 校验 → 逐格写 Cell 线字段 → world.line_changed。
## 免费：不扣资源、不返还（拆除同理）。校验在写之前完成，任一格不合法则整条不动。
func _place_line(world, kind: String, cells, dir_v) -> bool:
	if _grid_system == null:
		_reject(world, "GridSystem 未注册")
		return false
	var reason: String = _grid_system.can_place_line(world, cells, kind, dir_v)
	if not reason.is_empty():
		_reject(world, reason)
		return false
	var k := StringName(kind)
	var dir: Vector2i = dir_v
	for cell in cells:
		world.grid.set_line(cell, k, dir)
		world.line_changed.emit(cell, k)
	return true


## 拆除线路：格上有线才允许；清空线字段与块位，发 line_changed(cell, &"")。
## 重复格去重后处理：同一格只拆一次、只发一次信号（与 place_line 的 seen 校验对称）。
func _remove_line(world, cells) -> bool:
	if _grid_system == null:
		_reject(world, "GridSystem 未注册")
		return false
	var reason: String = _grid_system.can_remove_line(world, cells)
	if not reason.is_empty():
		_reject(world, reason)
		return false
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		world.grid.remove_line(cell)
		world.line_changed.emit(cell, &"")
	return true


## cell 参数归一化：Vector2i / Vector2 / [x, y]；非法返回 null。
func _cell_of(d: Dictionary):
	return _cell_value(d.get("cell", null))


## cells 参数归一化：[[x, y]...] → 强类型 Array[Vector2i]；非数组、空数组或含非法元素返回 null。
## 返回的数组直接喂给 GridSystem.can_place_line / can_remove_line（它们只吃 Vector2i 元素）。
func _cells_of(d: Dictionary):
	var v = d.get("cells", null)
	if not (v is Array) or (v as Array).is_empty():
		return null
	var out: Array[Vector2i] = []
	for item in v:
		var c = _cell_value(item)
		if c == null:
			return null
		out.append(c)
	return out


func _cell_value(v):
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and v.size() >= 2 \
			and (v[0] is int or v[0] is float) and (v[1] is int or v[1] is float):
		return Vector2i(int(v[0]), int(v[1]))
	return null


## dir 参数归一化：[dx, dy] / Vector2i / Vector2 → Vector2i；非法返回 null。
func _dir_of(d: Dictionary):
	var v = d.get("dir", null)
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and v.size() >= 2 \
			and (v[0] is int or v[0] is float) and (v[1] is int or v[1] is float):
		return Vector2i(int(v[0]), int(v[1]))
	return null


func _reject(world, reason: String) -> void:
	world.command_rejected.emit(reason)
