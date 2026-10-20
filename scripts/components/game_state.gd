class_name GameState
extends RefCounted
## 玩家级世界状态（§7）：资源钱包 + 全局状态。
## 非实体组件（手牌、钱包不是游戏世界对象），由关卡 bootstrap 创建并挂到 World.state。


const STATUS_PLAYING := "playing"
const STATUS_WON := "won"
const STATUS_LOST := "lost"

var level_id: StringName = &"" # 当前关卡（levels.json id）
var status: String = STATUS_PLAYING # playing | won | lost
var resources: Dictionary = {} # resource_id(StringName) -> int
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
