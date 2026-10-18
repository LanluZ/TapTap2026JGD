class_name ResourceBuffer
extends Component
## 资源缓冲（§4）：工厂产出先进缓冲，按 flush_interval 定期汇入玩家资源池（§7）。
##
## 任务 5「生产端物理化」（物流规格 §7）：water / ore 不再进资源池——
##   · 泵/矿机的**出料缓冲**放在 LogisticsSystem（容量 4，按块/秒吐到带/管），
##     本组件承载**进料库存**（装配台矿堆）与可汇入池的普通资源。
##   · 本组件的 cap 只约束物理资源（water/ore）：放不下就停产，绝不溢出丢弃。
##     cap = 0 表示「当前没有进料库存上限」（它不是接收判据：`world.deliver_ore`
##     先按配方把 cap 从 `ore_cap_of()` 同步过来，再判定放不放得下）。

var stored: Dictionary = {} # resource_id(StringName) -> int
var flush_interval: float = 0.0 # 汇入周期（秒，蓝图配置必填）
var flush_timer: float = 0.0
## 进料库存上限（装配台矿堆 6；0 = 不是进料库存）。
## **派生镜像**：权威来源是 `Production.recipe_id` → `ore_cap_of()`，由
## `sync_feed_stock()` 写入（Spawn 后的首个 Production tick 与 `world.deliver_ore`
## 两处都会调，故未跑过 tick 的新实体也不会读成 0）。
## 不要与 `LogisticsSystem.PRODUCER_BUFFER_CAPACITY`（泵/矿机**出料**缓冲 4）混淆。
## 只对物理资源（water / ore）生效：其他资源照旧定期汇入池，不做库存上限。
var cap: int = 0

## 物理资源：靠传送带/管道搬运，不汇入玩家资源池（§7 资源板移除水/矿）。
const PHYSICAL: Array = [&"water", &"ore"]
const ORE := &"ore"

## 进料库存规格（§7：装配台矿堆上限 6、开产耗 3 矿 + 池电 2）。
## 按**配方 id**取值（不特判实体 id）。recipes.json 只解析 inputs/outputs，
## 矿改传送带进料后配方里没有 ore 输入，故这三项记在组件侧当唯一数据源。
const RECIPE_ORE_STOCK := &"synth_special"
const ORE_STOCK_CAP := 6
const ORE_STOCK_COST := 3


## 物理资源判定（flush 跳过、本地库存截断的依据）。
static func is_physical(resource_id: StringName) -> bool:
	return PHYSICAL.has(resource_id)


## 该配方是否需要矿堆进料库存（0 = 不需要）。
static func ore_cap_of(recipe_id: StringName) -> int:
	return ORE_STOCK_CAP if recipe_id == RECIPE_ORE_STOCK else 0


## 该配方一次开产要消耗多少本地矿（0 = 不从库存扣矿）。
static func ore_cost_of(recipe_id: StringName) -> int:
	return ORE_STOCK_COST if recipe_id == RECIPE_ORE_STOCK else 0


## 按配方把 cap 刷成权威值（cap 只是 recipe_id 的镜像，不是判据本身）。
## 调用方：ProductionSystem.tick（每周期兜底）与 world.deliver_ore（放置当帧、
## 存档恢复等「还没跑过 Production tick」的路径）。返回刷新后的 cap。
func sync_feed_stock(recipe_id: StringName) -> int:
	cap = ore_cap_of(recipe_id)
	return cap


## 该资源的库存上限（0 = 不限）。
func limit_of(resource_id: StringName) -> int:
	return cap if is_physical(resource_id) else 0


func count_of(resource_id: StringName) -> int:
	return int(stored.get(resource_id, 0))


## 还能不能再放 amount 个（进料库存判据）。
func has_space_for(resource_id: StringName, amount: int = 1) -> bool:
	var lim := limit_of(resource_id)
	if lim <= 0:
		return true
	return count_of(resource_id) + maxi(amount, 0) <= lim


## 入库：返回实际入库量（受 cap 截断；0 = 已满 / 非法数量）。
func add(resource_id: StringName, amount: int) -> int:
	var want := maxi(amount, 0)
	var lim := limit_of(resource_id)
	if lim > 0:
		want = mini(want, maxi(lim - count_of(resource_id), 0))
	if want <= 0:
		return 0
	stored[resource_id] = count_of(resource_id) + want
	return want


## 出库（装配台开产扣矿）：返回实际取出量。
func take(resource_id: StringName, amount: int) -> int:
	var n := mini(maxi(amount, 0), count_of(resource_id))
	if n <= 0:
		return 0
	var left := count_of(resource_id) - n
	if left == 0:
		stored.erase(resource_id)
	else:
		stored[resource_id] = left
	return n
