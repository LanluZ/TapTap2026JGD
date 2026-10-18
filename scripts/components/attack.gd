class_name Attack
extends Component
## 工厂攻击（§4）。cooldown_left 为运行时冷却计时（关键字段之外的运行时状态）。

## 弹药上限（每发扣 1；world.deliver_ore 按此判「弹药满 → 拒收」，块滞留带端）。
## 权威常量只此一处：world.gd 以 const AttackScript = preload(...) 读它，勿在别处复制 6。
const AMMO_MAX := 6

var range: float = 0.0 # 攻击半径（世界单位）
var damage: float = 0.0
var cooldown: float = 0.0 # 两次发射间隔（秒）
var target_mask: int = 0 # 目标位掩码（GameConfig.MASK_*）
var targeting: StringName = &"nearest" # 瞄准策略（DNA 瞄准座：nearest/farthest/highest_hp/lowest_hp）
var projectile: StringName = &"" # 射弹定义 id（factories.json projectiles）
var hydro: StringName = &"hydro_none" # 亲水基因：hydro_love / hydro_thirsty / hydro_none（断水惩罚由系统读取）
var ammo: int = 0 # 弹药（矿）：每发扣 1；0 = 断弹（冷却 ×2 且伤害 ×0.5）
var cooldown_left: float = 0.0 # 剩余冷却
