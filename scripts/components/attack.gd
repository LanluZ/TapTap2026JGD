class_name Attack
extends Component
## 工厂攻击（§4）。cooldown_left 为运行时冷却计时（关键字段之外的运行时状态）。

var range: float = 0.0 # 攻击半径（世界单位）
var damage: float = 0.0
var cooldown: float = 0.0 # 两次发射间隔（秒）
var target_mask: int = 0 # 目标位掩码（GameConfig.MASK_*）
var targeting: StringName = &"nearest" # 瞄准策略（DNA 瞄准座：nearest/farthest/highest_hp/lowest_hp）
var projectile: StringName = &"" # 射弹定义 id（factories.json projectiles）
var cooldown_left: float = 0.0 # 剩余冷却
