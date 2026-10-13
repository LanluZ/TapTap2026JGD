class_name EntityLocator
extends RefCounted
## 实体 → 世界坐标解析（供 Targeting/Aura/Projectile 等系统与表现层共用）：
## 有 PathFollower 的实体沿路径弧长取点；有 GridPosition 的实体取格子中心。
## 返回 Vector2，无法定位时返回 null。


static func position(world, entity_id: int):
	if world == null:
		return null
	var follower = world.get_component(entity_id, &"PathFollower")
	if follower != null and world.path != null:
		return world.path.point_at(follower.distance)
	var gp = world.get_component(entity_id, &"GridPosition")
	if gp != null and world.grid != null:
		return world.grid.cell_to_world(gp.cell)
	return null
