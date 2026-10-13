class_name EntityLayer
extends Node2D
## 表现层（架构文档 §1）：逻辑实体 → 占位图 Sprite2D。只读世界，不写。
## 目前全部实体共用 icon.svg 占位（正式贴图就绪后按 Factory/Enemy 蓝图换图）。

const Placeholder := preload("res://icon.svg")

var world
var _sprites: Dictionary = {} # entity_id -> Sprite2D


func setup(w) -> void:
	world = w
	world.entity_destroyed.connect(_on_entity_destroyed)


func _process(_dt: float) -> void:
	if world == null:
		return
	for id in world.entity_ids():
		if not _sprites.has(id):
			_spawn(id)
	for id in _sprites:
		var pos = EntityLocator.position(world, id)
		if pos != null:
			(_sprites[id] as Sprite2D).position = pos


func _spawn(id: int) -> void:
	var s := Sprite2D.new()
	s.texture = Placeholder
	# 占位区分：敌人（沿路径）偏小偏红，工厂占格子 7 成，射弹最小
	if world.has_component(id, &"PathFollower"):
		s.scale = Vector2(0.35, 0.35)
		s.modulate = Color(1.0, 0.6, 0.6)
	elif world.has_component(id, &"Projectile"):
		s.scale = Vector2(0.15, 0.15)
		s.modulate = Color(0.7, 0.7, 0.7)
	else:
		s.scale = Vector2(0.7, 0.7)
	var pos = EntityLocator.position(world, id)
	if pos != null:
		s.position = pos
	add_child(s)
	_sprites[id] = s


func _on_entity_destroyed(id: int) -> void:
	if _sprites.has(id):
		(_sprites[id] as Sprite2D).queue_free()
		_sprites.erase(id)
