class_name CommandSystem
extends System
## #1 应用玩家指令（§5）。UI 层经 World.push_command 入队，本系统在每逻辑帧
## 最开始消费（§1「下一逻辑帧开始时执行」；CommandQueue 队列体在 World 上）。
##
## 指令协议（键名即协议，UI 层按此写入）：
##   {"type": "play_card",     "card_index": int, "cell": [x, y] 或 Vector2i}
##   {"type": "place_factory", "blueprint_id": String, "cell": [x, y] 或 Vector2i}
##   {"type": "place_tile",    "tile_type": String, "cell": [x, y] 或 Vector2i}
## 失败一律发 world.command_rejected(reason)：不改世界、不扣费（已扣则回滚）。

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
		_:
			_reject(world, "未知指令类型 '%s'" % str(d.get("type", "")))


## 打出卡牌（§8）：结算放置效果 → 扣卡费 → 手牌移除 → 登记补抽 1 张（CardSystem #10）。
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
	for spec in bp["components"]:
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
		_reject(world, "格子已被占用，无法放地块: %s" % str(cell))
		return false
	world.grid.set_tile(cell, StringName(tile_type))
	return true


## cell 参数归一化：Vector2i / Vector2 / [x, y]；非法返回 null。
func _cell_of(d: Dictionary):
	var v = d.get("cell", null)
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
