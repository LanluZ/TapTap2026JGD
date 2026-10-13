class_name System
extends RefCounted
## 系统基类（架构文档 §3）：RefCounted，无 Node。
## setup(world) 在全部系统注册后调用一次，用于装配跨系统引用；
## tick(world, dt) 由 World 按 §5 的固定顺序每逻辑帧调用。
## 参数保持无类型标注，避免与 world.gd 形成脚本级循环类型依赖。


func setup(_world) -> void:
	pass


func tick(_world, _dt: float) -> void:
	pass
