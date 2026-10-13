class_name Factory
extends Component
## 工厂通用实体标识（§4）：记录所属蓝图，功能由基因组（DNA 系统）表达的其他组件提供。
## genome：本实体的基因组（Array，座结构见 genes.json / Genome）；display_name：卡面名。

var blueprint_id: StringName = &""
var genome: Array = []
var display_name: String = ""
