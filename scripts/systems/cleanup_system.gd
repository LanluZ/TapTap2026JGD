class_name CleanupSystem
extends System
## #11 清理（§5）：统一销毁标记实体（§3「销毁延迟到帧末 cleanup」）、
## 移除过期 Effect（兜底扫描；正常过期回收在 AuraSystem #6）。


func tick(world, _dt: float) -> void:
	# 兜底：移除空 Effect 组件（过期条目由 AuraSystem 回收，这里只收组件壳）
	var empty_ids: Array = []
	for id in world.query(&"Effect"):
		var eff = world.get_component(id, &"Effect")
		if eff != null and eff.is_empty():
			empty_ids.append(id)
	for id in empty_ids:
		world.remove_component(id, &"Effect")
	# 帧末统一销毁（移除组件 → 释放 id → entity_died 之后的 entity_destroyed 信号）
	world.flush_destroyed()
