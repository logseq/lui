# UI as data：EDN view 实验

结论：**EDN 可以作为 LUI 的声明式 view 格式，但不应成为业务脚本语言。**
OCaml 持有 typed model、action、reducer、派生状态、异步任务；EDN 只描述结构、属性、绑定和事件路由。
本目录是实验，不是新增的正式 `lui` API；没有修改 dune 文件或生产依赖。

## 运行

需要项目依赖、`ocamlfind` 和 `melange-edn-core`。本次验证使用 OCaml 5.5.0 switch，
`ocaml-signal` 使用 `lui.opam.locked` 的 pin。若未安装 EDN reader，可固定到本实验使用的版本：

```sh
opam pin add --switch=5.5.0 melange-edn-core.0.5.0 \
  'git+https://github.com/logseq/melange-edn.git#3cb79f278e972388a0a2b2ea1caec7a008a0b956' -y
OPAMSWITCH=5.5.0 sh examples/data/run.sh
OPAMSWITCH=5.5.0 sh examples/data/run.sh --check
OPAMSWITCH=5.5.0 sh examples/data/run.sh examples/data/scenarios.edn --mount-only
```

`run.sh` 用现有 dune target 构建 `lui.cmxa`，再以 `ocamlfind` 编译解释器和示例，
产物只写入 `_build/data-view`。默认示例使用真实 `Lui_app` 和 headless patch backend，
模拟输入、添加、勾选和重排，**不会打开图形窗口**。
`--mount-only` 使用一个示例条目，只挂载指定文档，不执行默认 todo 交互。

## 数据流与边界

```text
OCaml typed model ── project ──> EDN-compatible read model
                                     │
EDN source ── compile ──> view plan ── bindings / keyed scopes ──> LUI retained patches
                                     │
                              action name + current arguments + native event
                                     │
OCaml dispatch ──> typed action ──> reducer ──> model signal
```

`main.ml` 是完整的 OCaml model / reducer / action decoder；`todos.edn` 不含计算逻辑。
例如 `can-add?`、`empty?` 和统计文案都由 OCaml `project` 产生，而不是在 EDN 中拼表达式。
projection 应只暴露 view 所需的数据，不必序列化整个业务 model。

```ocaml
Data_view.compile ~actions:["remove"] source
Data_view.render document ~model ~project ~dispatch
```

`compile` 返回 `(t, string) result`。`dispatch` 接收白名单 action 名、EDN 参数列表和原始
`Lui_protocol.event`，由 OCaml 检查参数类型、数量与事件 payload，再构造 typed action。
白名单只控制可调用的名字，不代替业务授权。

## View 语法

```edn
{:version 1
 :components
 {:entry
  [:row
   [:text-field {:text {:bind [:props :title]}}]
   [:button {:text "Remove"
             :on {:press [:remove {:bind [:props :id]}]}}]]}
 :view
 [:column {:gap 8 :padding 16}
  [:when {:bind [:model :empty?]}
   [:text {:text "Nothing here"}]]
  [:for {:items {:bind [:model :items]} :as :item :key [:id]}
   [:use :entry {:id {:bind [:item :id]}
                 :title {:bind [:item :title]}}]]]]}
```

- 元素：`[:kind {:property value ...} child ...]`；属性 map 可省略，children 必须是 view vector。
  kind 和 property 使用 `Lui_wire_schema` 的 wire 名字，而非 OCaml 构造器参数名。
- 文档：版本化 map；也接受单个根 view vector，方便片段实验。根 `:root` 保留给 runtime。
- 绑定：`{:bind [:model :field]}`、`{:bind [:props :field]}`、`{:bind [:item :field]}`。
  path 支持嵌套 map 和 vector 整数下标；缺失路径是错误，不会静默转成空字符串。
- 属性：string、keyword、boolean、整数、有限浮点数；keyword 转 wire string，
  整数在目标属性需要 float 时提升为 float。`nil` 删除属性，不表示隐藏元素。
- 条件：`[:when boolean-expression child]`。无 else 或通用表达式，复杂条件由 OCaml 投影。
- 列表：`:items` 必须是 vector，`:key` 是条目内路径；key 必须是 string、keyword 或整数且唯一。
  列表别名不能占用 `:model` / `:props`；嵌套列表可使用不同别名访问外层条目。
- 复用：`[:use :component props-map]`，调用时的值在组件里以 `:props` 读取；拒绝递归展开。
- 事件：`:on {:press :add}` 或 `:on {:input [:rename {:bind [:props :id]}]}`。
  输入文本、checkbox 值、pointer 数据等从原始 event 交给 OCaml，不发明 EDN payload 表达式。
  参数在**事件触发时**采样当前 scope，不捕获初次挂载时的旧条目。
- 扩展：`:ext/<registered-name>` 转发到现有 extension registry；schema、平台能力、属性类型、
  children 和 event admission 最终由 LUI runtime 检查。原型未提供扩展注册示例。

常用事件为 `:press`、`:input`、`:submit`、`:toggle`、`:value`、`:change`、`:dismiss`。
也提供 pointer、导航、滚动、文件选择等已有 protocol event 的映射，见 `event_specs`；
标准 kind 不接受不兼容事件。事件 admission flag 由 `:on` 自动配置。

## 已验证与适用范围

| 场景 | 结果与证据 | 边界 |
| --- | --- | --- |
| 表单、启用状态、输入事件 | todo 示例：绑定 draft，OCaml 校验，input / submit / press 路由 | 输入法、焦点、selection 尚未做平台交互验证 |
| keyed 编辑列表 | `check.ml`：重排产生 move；输入框 id 不变；属性原位更新；事件读取更新后的条目；删除条目释放节点 | 验证 retained contract，不等于证明焦点跨平台无损 |
| 条件 / 空态 | todo 示例初始空态，添加首项后移除 | 只提供单分支；不保留隐藏分支的局部 UI 状态 |
| 组件复用 | todo 行经过 `:use` / `:props`，覆盖绑定及最新事件参数 | 暂无 slots、动态组件名、局部 state |
| split、tabs、表格、树、slider、select、virtual-list | `scenarios.edn` 在 generic headless backend 通过 schema 和挂载 | 只验证表示和挂载；不代表完整交互、虚拟化性能或平台 parity |
| 对话框、菜单、异步 loading/error | 可由 OCaml model 投影开关、数据和命令，EDN 用 `:when` / 标准 kind 表示 | 实际弹层、键盘与 async 场景未端到端验证 |
| 文件、媒体、自定义编辑器 | wire scalar / 资源 id，或预注册 extension 作为出口 | 资源生命周期、编辑器内部状态仍由 OCaml / host 管理；未验证 |

本实验没有浏览器、iOS 或 native GUI 的验证结果。不能据此声称覆盖“所有场景”。

## 校验与仍需解决的问题

编译期检查文档版本、重复字段、未知 kind / property / action、字面量 scalar、children 的 kind
关系及组件展开；依赖 model 的路径、类型、条件和重复列表 key 在投影时检查。
标准属性组合和 event admission 也在挂载/更新前检查，最终仍使用 runtime 的平台校验。
错误目前是文本或运行时异常，没有文件行列、类型化 binding schema 或更新事务回滚保证。
未激活条件里的绑定只在该条件激活时检查；未引用组件不会展开。

解释器中的 `Signal.map` / `Lui_dynamic` 是 scope-owned runtime 桥接，不是应用手写 reactive
view；应用只提供 `project` / `dispatch`。不调用 `Lui_elements.dyn`，也不接管调用者 model signal。

- 没有算术、函数调用、`eval`、闭包、任意 OCaml 函数查找或代码加载；不要逐步加成第二门语言。
- 没有热替换 EDN 文档 / 热重载状态迁移；当前 `t` 在挂载期间固定。
- 没有任意 map/vector wire 属性；结构化属性须遵循现有 protocol 的编码，而非直接塞 EDN map。
- 每次 model 变化会重新投影和遍历活动 view；列表把完整环境传入行 scope。
  大 model / 大列表需测量 projection、validation、key diff 和分配成本，再做依赖切片。
- 1 MiB 源码限制、128 层 view 展开限制只是实验防误用措施，不是抗恶意 EDN parser 的沙箱。
  不应直接加载不可信远程文档；生产化需 parser/AST/node 数量预算、权限和错误隔离。

建议下一步先选一个真实页面做实际 backend parity 验证，再决定是否把格式提升为正式 library。
优先补 binding/action schema、错误定位和 typed OCaml projection 辅助；不优先添加 EDN 计算 DSL。
