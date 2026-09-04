# 项目协作约定

## 项目边界

- 本仓库是《八方旅人 II》的独立游戏 Mod。
- 首选 UE4SS Lua 运行时挂钩；只有原生 C 菜单无法稳定扩展时，才增加 Blueprint/PAK 覆盖层。
- Mod 不读写 `SaveGames`，也不调用自动保存、剧情旗标、物品、金钱或任务进度写入接口。
- 句子回看只操作演出、镜头、对话框、语音与普通音效，不回退全局剧情执行索引。

## 修改原则

- 功能和设计变化时同步更新 `README.md`、`README.en.md` 和 `docs/architecture.md`。
- 以当前工作区为准继续修改，不用旧内容覆盖人工调整。
- 代码与现状文档只保留当前实现；已删除、失败和过渡方案不保留探测、计数、兼容分支、版本叙述或变更过程。研究记录按当前确认事实整理。
- 常规改动只做与改动点直接相关的必要检查；不做“安装→卸载→重装”往返验证，不重复执行相同检查，也不追加无关全量测试。
- 默认不创建或保留 `tests/`、`validate.*`、测试框架、测试快照及为证明改动而新增的验证脚本；只有用户明确要求具体测试时才增加对应检查。
- 除非用户明确要求，不生成安装差异、验证记录、补丁副本、测试快照、独立回滚脚本、临时制品或 `artifacts/` 目录。
- 安装与卸载只保留运行所需的最小状态；临时文件用完立即清理，不作为项目产物保留。
- 当前分析确需保留的解包资源和中间文件放在本项目 `temp/`，保持 Git 忽略；不用系统临时目录。
- 支持范围必须标明游戏 build；发现主程序哈希变化时停止安装并重新验证对象布局。
- 每次完成修改时，按 `docs/architecture.md` 的“按修改内容选择步骤”明确说明：改了哪些源文件、是否需要更新 PAK、是否需要重新构建图形安装器、是否需要重新生成 TSV，以及本机验证或正式发布应运行的下一条命令。不要把 Lua 更新描述成 PAK 更新，也不要让用户重复执行发布脚本已经自动编排的单项构建。

## 目录职责

- `assets/`：README 使用的图片，纳入 Git，并由发布脚本按原相对路径放入发布 ZIP。
- `mod/`：发布暂存输入；`Scripts/` 中的 `main.lua` 与 `config.lua` 是源码，查询 TSV 是本机构建结果；`pak/` 中的 PAK 和 `runtime/UE4SS/` 中的第三方运行包同样是本机构建或获取结果。安装脚本把这些内容映射到各自的游戏目录。
- `temp/`：本机分析中间文件，不纳入 Git。
- `scripts/install.ps1`、`uninstall.ps1` 与 `common.ps1`：安装、卸载和共享安装约束；其他根脚本负责编排运行时获取与发布打包。
- `scripts/build_official_texts/`：发布前生成九种官方文本查询文件的构建脚本和说明，不参与用户安装。
- `scripts/build_pak/`：`source/` 保存纳入版本控制的四个覆盖 PAK 源资产，构建脚本从中生成 Git 忽略的 PAK。
- `scripts/analysis/`：线下台词解析工作区；`scripts/analysis/tools/` 中保留解析工具和说明，生成的 manifest、input 与 results 保持 Git 忽略。
- `scripts/installer/`：Windows 图形安装器源码和无参数构建脚本；根目录生成的 EXE 只进入发布包。
- `scripts/fetch-ue4ss.ps1`：下载并校验固定版本 UE4SS；下载结果保持 Git 忽略。
- `scripts/build-release.ps1`：重新生成 PAK 和安装器、准备运行时并把最终安装包写入 Git 忽略的 `dist/`。
- `docs/`：当前架构、完整开发流程和已经确认的逆向证据。

## 文档职责

- `README.md` 与 `README.en.md` 分别面向中文和英文使用者，只写当前功能、游戏内配置、安装、更新和卸载，并保持内容一致。
- `docs/architecture.md` 面向开发者，写当前架构、数据流、修改入口、构建顺序、针对性验证和发布边界。
- `docs/research.md` 只整理目标 build 已确认的 UObject、函数、字段、资源路径和行为。
- `scripts/build_official_texts/README.md` 与 `scripts/analysis/tools/README.md` 分别维护各自工具的参数、格式和操作细节。
