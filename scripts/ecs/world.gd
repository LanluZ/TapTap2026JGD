class_name World
extends RefCounted
## ECS 世界内核（架构文档 §3）：实体生命周期、组件存储、系统调度、信号通信。
## 本文件不含任何游戏规则；config/state/path/grid 是游戏层在 bootstrap 时
## 注入的挂载点，内核只持有 RefCounted 引用、不解释其类型。

signal entity_created(entity_id: int)
signal entity_destroyed(entity_id: int)
signal entity_died(entity_id: int)
signal wave_completed(wave_index: int)
signal game_won
signal game_lost
signal resource_gained(resource_id: StringName, amount: int)
signal command_rejected(reason: String)
## 线路变更（物流数据层）：放置/拆除管道·传送带后逐格通知。
## kind: &"pipe" / &"belt" = 放置；&"" = 该格线路被拆除。
signal line_changed(cell: Vector2i, kind: StringName)
## 矿块交付（传送带端头对接建筑）：entity_id = 接收方实体。
## 任务 3 只发信号；任务 6 在此之后实装弹药/库存填充。
signal ore_delivered(entity_id: int)

## —— 游戏层挂载点（由关卡 bootstrap 注入）——
var config: RefCounted = null # GameConfig
var state: RefCounted = null # GameState
var path: RefCounted = null # RingPath
var grid: RefCounted = null # GridMapData
var logistics: RefCounted = null # LogisticsSystem（由它自己 setup 时回填，供后续任务查询）

## 指令队列（§1：玩家操作统一进 CommandQueue，下一逻辑帧开始时执行）。
## UI 层 push_command 写入；CommandSystem（#1）在 tick 开始时取走。
var commands: Array = []

## 系统列表：按添加顺序固定执行（§5 的 11 系统顺序由 bootstrap 保证）。
var systems: Array = []

var _next_id: int = 1
var _alive: Dictionary = {} # entity_id -> true
var _pending_destroy: Array = [] # 延迟到帧末 cleanup（CleanupSystem #11）
var _stores: Dictionary = {} # 组件类型(StringName) -> Dictionary[entity_id -> Component]
var _entity_masks: Dictionary = {} # entity_id -> int 组件位掩码


# ---------------------------------------------------------------- 实体生命周期

func create_entity() -> int:
	var id: int = _next_id
	_next_id += 1
	_alive[id] = true
	_entity_masks[id] = 0
	entity_created.emit(id)
	return id


## 标记销毁：立即从 is_alive 消失，组件与存储在帧末 cleanup 统一移除（§3）。
func destroy_entity(id: int) -> void:
	if not _alive.has(id) or _pending_destroy.has(id):
		return
	_pending_destroy.append(id)


func is_alive(id: int) -> bool:
	return _alive.has(id) and not _pending_destroy.has(id)


func is_pending_destroy(id: int) -> bool:
	return _pending_destroy.has(id)


func entity_count() -> int:
	return _alive.size()


## 帧末清理：移除待销毁实体的全部组件（由 CleanupSystem 在 #11 调用）。
func flush_destroyed() -> void:
	if _pending_destroy.is_empty():
		return
	var list: Array = _pending_destroy
	_pending_destroy = []
	for id in list:
		for t in _stores:
			(_stores[t] as Dictionary).erase(id)
		_alive.erase(id)
		_entity_masks.erase(id)
		entity_destroyed.emit(id)


# ---------------------------------------------------------------- 组件存储

## 存储结构（§3）：按组件类型一张 Dictionary[entity_id, Component]，
## 外层 _stores 即类型索引。约束：同实体同类型只保留一个组件实例
## （多来源效果由 Effect 组件内部条目承载，见 effect.gd 注释）。
## 纪律：不要在迭代 query(T) 的同时增删类型 T 的组件。
func add_component(id: int, comp: Component) -> Component:
	if comp == null:
		push_error("World.add_component: comp 为空")
		return null
	var t: StringName = Component.type_of(comp)
	if not _stores.has(t):
		_stores[t] = {}
	(_stores[t] as Dictionary)[id] = comp
	_entity_masks[id] = int(_entity_masks.get(id, 0)) | Entity.bit_for(t)
	return comp


func remove_component(id: int, t: StringName) -> void:
	if _stores.has(t):
		(_stores[t] as Dictionary).erase(id)
	if _entity_masks.has(id):
		_entity_masks[id] = int(_entity_masks[id]) & ~Entity.bit_for(t)


func has_component(id: int, t: StringName) -> bool:
	return _stores.has(t) and (_stores[t] as Dictionary).has(id)


func get_component(id: int, t: StringName) -> Component:
	if not _stores.has(t):
		return null
	return (_stores[t] as Dictionary).get(id, null)


## 类型索引查询：返回活的 {entity_id -> Component}（共享引用，只读语义）。
func query(t: StringName) -> Dictionary:
	if not _stores.has(t):
		_stores[t] = {}
	return _stores[t]


## 实体组件位掩码（§2 entity.gd 位标记）。
func mask_of(id: int) -> int:
	return int(_entity_masks.get(id, 0))


func entity_ids() -> Array:
	return _alive.keys()


## 矿块交付（传送带端头对接建筑时由 LogisticsSystem 调用）：任务 5 实装分流。
## 返回 false = 本帧不接收 → 块留在端头等待（不吞、不算掉落）。
##   ① 有 Attack（炮塔）：弹药填充是任务 6，本任务先不接收（false），避免矿被静默吞掉；
##   ② 有 Production 且配方带矿堆进料（装配台 synth_special）：进本地库存
##      （ResourceBuffer.stored.ore，上限 6，见 ResourceBuffer.ore_cap_of），满则 false；
##   ③ 其余（发电机/光环/无进料配方）：false。
## 进料库存以 ResourceBuffer.cap > 0 为标志，由 ProductionSystem 按配方写入（单一判据）。
func deliver_ore(entity_id: int) -> bool:
	if not is_alive(entity_id):
		return false
	if has_component(entity_id, &"Attack"):
		return false # 任务 6：填弹药（届时改为弹药满才拒收）
	var buffer = get_component(entity_id, &"ResourceBuffer")
	if buffer == null or int(buffer.cap) <= 0:
		return false
	if buffer.add(&"ore", 1) <= 0:
		return false # 库存满：块留在端头
	ore_delivered.emit(entity_id)
	return true


## 供水查询（任务 4）：实体是否在水网扩散集合内。数据由 LogisticsSystem 每 tick 全量重算
## （无向 BFS，无脏标记）；LogisticsSystem 未注册或实体不在真值表里 → false。
## 任务 6 的嗜水判定（hydro_love 加速 / hydro_thirsty 无水停摆）读这里。
func is_watered(entity_id: int) -> bool:
	if logistics == null:
		return false
	return logistics.is_watered(entity_id)


# ---------------------------------------------------------------- 指令队列

func push_command(cmd: Dictionary) -> void:
	commands.append(cmd)


func drain_commands() -> Array:
	var out: Array = commands
	commands = []
	return out


# ---------------------------------------------------------------- 系统调度

func add_system(s) -> void:
	systems.append(s)


## 全部系统注册完成后调用一次（保证 setup 内 get_system 能找到同伴）。
func setup() -> void:
	for s in systems:
		s.setup(self)


func get_system(type_name: String):
	for s in systems:
		var sp: Script = s.get_script()
		if sp != null and String(sp.get_global_name()) == type_name:
			return s
	return null


## 按 §5 固定顺序执行系统；销毁延迟到 #11 CleanupSystem。
func tick(dt: float) -> void:
	for s in systems:
		s.tick(self, dt)
