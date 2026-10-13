class_name MovementSystem
extends System
## #3 移动（§5）：沿环形路径推进；应用减速地块；累计圈数 laps_done。
## 字段归属说明：§5 把 laps_done 计入本系统、§4 把字段列在 Enemy 组件——
## 本实现推进 PathFollower.distance、在跨圈时回写 Enemy.laps_done，兼容两处。

var _tile_types: Dictionary = {} # 关卡 tile_types（减速带数值在 levels.json）


func setup(world) -> void:
	if world.config == null or world.state == null:
		push_error("MovementSystem.setup: World 未挂载 config/state")
		return
	var level: Dictionary = world.config.get_level(world.state.level_id)
	if level.is_empty():
		return
	_tile_types = level["tile_types"]


func tick(world, dt: float) -> void:
	if world.path == null or world.path.total_length <= 0.0:
		return
	var total: float = world.path.total_length
	for id in world.query(&"PathFollower"):
		if not world.is_alive(id):
			continue
		var pf = world.get_component(id, &"PathFollower")
		var mult := 1.0
		# 减速地块：读网格数据（地块非实体，§4）
		if world.grid != null:
			var cell: Vector2i = world.grid.world_to_cell(world.path.point_at(pf.distance))
			var c = world.grid.get_cell(cell)
			if c != null and c.tile_type != &"":
				var td = _tile_types.get(c.tile_type, null)
				if td != null:
					mult *= float(td["speed_mult"])
		# 敌人 DEBUFF（AuraSystem 施加的 move_speed_mult）
		var eff = world.get_component(id, &"Effect")
		if eff != null and eff.has_stat(GameConfig.STAT_MOVE_SPEED_MULT):
			mult *= eff.get_value(GameConfig.STAT_MOVE_SPEED_MULT)
		pf.distance += pf.speed * mult * dt
		while pf.distance >= total: # 允许单帧跨多圈
			pf.distance -= total
			var en = world.get_component(id, &"Enemy")
			if en != null:
				en.laps_done += 1
