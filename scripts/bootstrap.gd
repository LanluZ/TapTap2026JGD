class_name Bootstrap
extends RefCounted
## 关卡世界组装（架构文档 §5 固定顺序 11 系统）：
## tests/smoke.gd 与 Game 节点（scripts/game.gd）共用，避免两处清单漂移。


static func build_world(config: GameConfig, level_id: StringName = &"level_1") -> World:
	var state := GameState.new()
	state.level_id = level_id
	var level: Dictionary = config.get_level(level_id)
	if level.is_empty():
		push_error("Bootstrap: 未定义关卡 %s" % String(level_id))
		return null
	var ring := RingPath.new()
	if not ring.build(level["path_id"], level["path"]):
		push_error("Bootstrap: 环形路径构建失败（%s）" % String(level_id))
		return null
	var grid := GridMapData.new()
	grid.setup(float(level["cell_size"]))
	for c in level["buildable_cells"]:
		grid.set_buildable(c)
	for c in level["path_cells"]:
		grid.ensure_cell(c)
	for t in level["tiles"]:
		grid.set_tile(t["cell"], t["tile_type"])
	var world := World.new()
	world.config = config
	world.state = state
	world.path = ring
	world.grid = grid
	world.add_system(CommandSystem.new()) # 1
	world.add_system(WaveSystem.new()) # 2
	world.add_system(MovementSystem.new()) # 3
	world.add_system(GridSystem.new()) # 4
	world.add_system(ProductionSystem.new()) # 5
	world.add_system(AuraSystem.new()) # 6
	world.add_system(TargetingSystem.new()) # 7
	world.add_system(ProjectileSystem.new()) # 8
	world.add_system(DamageSystem.new()) # 9
	world.add_system(CardSystem.new()) # 10
	world.add_system(CleanupSystem.new()) # 11
	world.setup()
	return world
