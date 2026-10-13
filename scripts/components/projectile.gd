class_name Projectile
extends Component
## 射弹（§4）。position：飞行坐标（§4 关键字段之外的运行时状态，飞行必需）。
## 命中后把 damage 记入目标 Health.pending_damage，由 DamageSystem（#9）结算。

var target: int = 0 # 目标实体 id
var damage: float = 0.0
var speed: float = 0.0 # 世界单位/秒（factories.json projectiles）
var position: Vector2 = Vector2.ZERO
