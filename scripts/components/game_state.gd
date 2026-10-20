class_name GameState
extends RefCounted
## 玩家级世界状态（§7）：资源钱包 + 全局状态。
## 非实体组件（手牌、钱包不是游戏世界对象），由关卡 bootstrap 创建并挂到 World.state。


const STATUS_PLAYING := "playing"
const STATUS_WON := "won"
const STATUS_LOST := "lost"

## 电力购买敌人上限：每次 +ENEMY_CAP_STEP 个同时在场名额，
## 价格 = round(ln(e + 已购次数×3))（电力，次数从 0 起 ⇒ 首件 1 电）。
const ENEMY_CAP_STEP := 2
const EULER := 2.718281828459045

var level_id: StringName = &"" # 当前关卡（levels.json id）
var status: String = STATUS_PLAYING # playing | won | lost
var resources: Dictionary = {} # resource_id(StringName) -> int
var enemy_cap: int = 0 # 同时在场敌人上限（失败线）：关卡接线写入，可购买提升；0 = 未接线
var enemy_cap_buys: int = 0 # 已购买次数（价格随次数上涨）
var waves_survived: int = 0 # WaveSystem 写入，供 UI 读取
var enemies_on_path: int = 0 # WaveSystem 每帧写入
var fusion_seed: int = 0 # 融合种子（DNA 系统）：0 = 每次随机；非 0 = 可复现
var fusion_charge: float = 0.0 # 融合充能已累计（游戏秒，cards.json fusion_charge_seconds 为满值）
var fusion_opportunity: bool = false # 融合机会就绪：充能满置 true，fuse 指令成功后置 false
var waves_running: bool = true # 波次开关：关卡接线（Game._ready）开局置 false = 默认暂停
var speed: float = 1.0 # 倍速：UI 速度按钮切换 1/2


func is_playing() -> bool:
	return status == STATUS_PLAYING


## 融合机会充能（游戏时间，接线层每帧喂 dt×speed）：已有机会不再累计；
## 攒满 interval 得一次机会，进度清零。机会上限 1 次（满了不囤）。
func charge_fusion(dt: float, interval: float) -> void:
	if fusion_opportunity or interval <= 0.0 or dt <= 0.0:
		return
	fusion_charge += dt
	if fusion_charge >= interval:
		fusion_charge = 0.0
		fusion_opportunity = true


func get_amount(resource_id: StringName) -> int:
	return int(resources.get(resource_id, 0))


func add(resource_id: StringName, amount: int) -> void:
	resources[resource_id] = get_amount(resource_id) + amount


func can_afford(cost: Dictionary) -> bool:
	for rid in cost:
		if get_amount(StringName(rid)) < int(cost[rid]):
			return false
	return true


## 足额则扣除并返回 true；不足则不动钱包返回 false。
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for rid in cost:
		var rid_s := StringName(rid)
		resources[rid_s] = get_amount(rid_s) - int(cost[rid])
	return true


## 仅用于指令失败回滚（如卡牌已扣费但放置失败）。
func refund(cost: Dictionary) -> void:
	for rid in cost:
		add(StringName(rid), int(cost[rid]))


## 购买敌人上限的价格（电力）：round(ln(e + 已购次数×3))，至少 1。
## 序列（次 0..）：1, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4 …
static func enemy_cap_price(buys: int) -> int:
	return maxi(1, int(roundf(log(EULER + float(maxi(buys, 0) * 3)))))


## 用电购买敌人上限：池里电够则扣款并 +ENEMY_CAP_STEP，返回是否成交。
## 买不起时钱包与上限都不动（价格按当前已购次数算，不与 UI 显示解耦）。
func buy_enemy_cap() -> bool:
	if not pay({&"power": enemy_cap_price(enemy_cap_buys)}):
		return false
	enemy_cap_buys += 1
	enemy_cap += ENEMY_CAP_STEP
	return true
