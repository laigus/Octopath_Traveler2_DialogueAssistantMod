# 架构

## 边界

本项目是独立游戏 Mod：

```text
游戏原生 Event/RichEvent
  → UE4SS UFunction Hook
  → 句子边界与演出帧记录
  → 原生 Sequence Player / TalkText / Voice 调用
  → 游戏原生键帽提示 / 官方翻译与解析帮助框 / 设置页 Mod 配置
```

## 文档职责

- `README.md` 与 `README.en.md` 分别面向中文和英文使用者，只说明当前功能、游戏内配置、安装、更新和卸载，并保持内容一致。
- 本文面向开发者，记录当前架构、数据来源、修改入口、构建顺序、针对性验证和发布边界。
- `docs/research.md` 只记录已经从目标 build 确认的 UObject、函数、字段、资源路径和行为。
- `scripts/build_official_texts/README.md` 说明官方文本查询文件的单项构建工具。
- `scripts/analysis/tools/README.md` 说明台词解析数据的输入格式、Agent 输出约束和合并工具。
- `scripts/build_pak/` 从纳入版本控制的源资产生成覆盖 PAK。
- `scripts/installer/` 维护 Windows 图形安装入口的源码和构建方式。
- `scripts/build-release.ps1` 负责编排 PAK、UE4SS、安装器与已有 TSV 发布输入，并创建最终发布 ZIP。

## 版本控制、发布输入与安装映射

Git 保存必要源码、构建脚本、文档和 PAK 源资产；生成数据、编译结果、下载的第三方运行包和最终压缩包保持忽略：

| 路径 | 来源 | Git | 发布包 |
| --- | --- | --- | --- |
| `assets/` | README 使用的图片 | 纳入 | 包含 |
| `mod/Scripts/main.lua`、`config.lua` | 手工维护 | 纳入 | 包含 |
| `scripts/build_pak/source/` | 经 UAssetGUI 编辑的四个 PAK 源资产 | 纳入 | 不直接包含 |
| `mod/Scripts/official_*.tsv` | 从受支持游戏 build 生成 | 忽略 | 包含 |
| `scripts/analysis/{ja,en}/` 的 input、results、manifest | 从官方文本与 Agent 结果生成 | 忽略 | 不包含 |
| `mod/Scripts/analysis_ja.tsv` | 从完整 Agent 结果生成 | 忽略 | 包含 |
| `mod/pak/OctopathDialogueAssistant_P.pak` | 从 `scripts/build_pak/source/` 生成 | 忽略 | 包含 |
| `mod/runtime/UE4SS/` | 从固定上游版本下载并校验 | 忽略 | 包含 |
| `OctopathDialogueAssistantInstaller.exe` | 从 `scripts/installer/Program.cs` 编译 | 忽略 | 包含 |
| `dist/` | `scripts/build-release.ps1` 的输出 | 忽略 | GitHub Release 资产 |

完成构建后，工作区中的 `mod/` 是安装脚本使用的发布输入，但它不直接镜像游戏目录。安装器按用途映射各部分：

| 仓库路径 | 游戏目标路径 |
| --- | --- |
| `mod/Scripts/` | `Octopath_Traveler2/Binaries/Win64/Mods/OctopathDialogueAssistant/Scripts/` |
| `mod/runtime/UE4SS-settings.ini` | `Octopath_Traveler2/Binaries/Win64/UE4SS-settings.ini` |
| `mod/pak/OctopathDialogueAssistant_P.pak` | `Octopath_Traveler2/Content/Paks/OctopathDialogueAssistant_P.pak` |
| `mod/runtime/UE4SS/3.0.1/UE4SS_v3.0.1.zip` 中固定的加载文件 | `Octopath_Traveler2/Binaries/Win64/` |

`OctopathDialogueAssistant` 作为游戏 `Mods/` 下的安装目录名，由安装器根据 `scripts/common.ps1` 中的 `ModName` 建立；仓库源文件不增加同名中间目录。

## 开发流程

### 1. 确认目标 build

`scripts/common.ps1` 固定受支持游戏的 EXE、主 PAK、UE4SS 压缩包和运行 DLL 哈希。`scripts/install.ps1` 与 `scripts/build_official_texts/build.ps1` 都通过 `Resolve-GameLayout` 校验这些对象。

游戏更新后，先重新确认 `docs/research.md` 中使用的 UFunction、字段布局、Blueprint 类和 PAK 虚拟路径，再更新固定哈希；不要只修改哈希以绕过 build 检查。

### 2. 选择修改层

- 剧情捕获、历史记录、重播、官方翻译、解析面板、快捷键和设置页交互修改 `mod/Scripts/main.lua`。
- 默认开关、按键和语言修改 `mod/Scripts/config.lua`；安装更新会保留游戏目录中已有的用户配置。
- 只有设置页分类注册或复合字体映射变化时才更新 `scripts/build_pak/source/` 中的源资产并重新生成 PAK。
- 游戏官方文本表或受支持 build 变化时才重新生成九种 `official_*.tsv`。
- Agent 解析结果变化时，从对应语言的独立数据集重新生成解析查询表；当前发布运行时使用 `analysis_ja.tsv`。

运行时代码不访问 `SaveGames`，也不写剧情旗标、任务、物品、金钱或全局剧情执行索引。

### 3. 按修改内容选择步骤

先区分三个动作：

- **更新 PAK**：把 `scripts/build_pak/source/` 中的四个 Unreal 资产重新打成 `mod/pak/OctopathDialogueAssistant_P.pak`。Lua、配置和 TSV 都不在这个 PAK 中。
- **构建安装器**：把 `scripts/installer/Program.cs` 编译为 `OctopathDialogueAssistantInstaller.exe`。该 EXE 只是相邻 `scripts/install.ps1` 与 `scripts/uninstall.ps1` 的图形前端，不内嵌 Lua、TSV、PAK 或 UE4SS。
- **生成发布包**：`scripts/build-release.ps1` 会统一重新生成 PAK、准备 UE4SS、重新编译安装器并创建 ZIP，因此正式发布前不需要先手动执行 PAK 和安装器的单项构建命令。该命令仍需能够从 `PATH`、`REPAK_PATH` 或 `-RepakPath` 找到 repak；九种官方文本 TSV 和日语解析 TSV 不由该脚本生成，也必须已经存在。

| 修改内容 | 要单独更新 PAK | 要单独构建安装器 | 更新本机游戏用于验证 | 生成发布 ZIP |
| --- | --- | --- | --- | --- |
| `mod/Scripts/main.lua` | 否 | 否 | 运行 `scripts/install.ps1` | 直接运行 `scripts/build-release.ps1` |
| `mod/Scripts/config.lua` | 否 | 否 | 只影响不存在配置时的新安装；更新安装会保留现有用户配置 | 直接运行 `scripts/build-release.ps1` |
| `mod/Scripts/official_*.tsv` 的数据来源或目标游戏 build | 否 | 否 | 先运行 `scripts/build_official_texts/build.ps1`，再运行 `scripts/install.ps1` | 先生成九种 TSV，再运行 `scripts/build-release.ps1` |
| `scripts/analysis/{ja,en}/` 的输入、结果或合并逻辑 | 否 | 否 | 先校验并用 `dataset.py build-runtime` 更新运行时 TSV，再运行 `scripts/install.ps1` | 先生成所需运行时 TSV，再运行 `scripts/build-release.ps1` |
| `scripts/build_pak/source/` 中的设置页或字体资产 | 是 | 否 | 先运行 `scripts/build_pak/build.ps1`，再运行 `scripts/install.ps1` | 直接运行 `scripts/build-release.ps1`，它会重新生成 PAK |
| `scripts/installer/Program.cs` | 否 | 是 | 运行 `scripts/installer/build.ps1` 后直接测试 EXE | 直接运行 `scripts/build-release.ps1`，它会重新编译安装器 |
| `scripts/install.ps1`、`uninstall.ps1` 或 `common.ps1` | 否 | 否；EXE 会在运行时调用这些脚本 | 只运行本次修改涉及的安装或卸载命令 | 直接运行 `scripts/build-release.ps1`，更新后的脚本会进入 ZIP |
| `mod/runtime/UE4SS-settings.ini` 或 `scripts/common.ps1` 中固定的 UE4SS 版本 | 否 | 否 | 按改动准备对应运行时，再验证安装 | 运行 `scripts/build-release.ps1`；它会下载或复用并校验固定运行时 |
| `README.md` 或 `README.en.md` | 否 | 否 | 不安装 | 只有需要把新 README 放进发布 ZIP 时才重新打包 |
| `docs/` | 否 | 否 | 不安装 | 不进入发布 ZIP，只需提交到源码仓库 |

最常用的两条命令是：

```powershell
# 把当前工作区的运行文件更新到本机游戏；不会生成发布 ZIP
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 `
  -GameRoot "<Steam common 下的 Octopath_Traveler2 目录>"

# 生成正式发布 ZIP；PAK、UE4SS 和图形安装器由该命令统一处理
powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1 -Version "<版本号>"
```

因此，只修改 `main.lua` 时：本机验证只需重新运行安装命令；要生成对外发布包时，只需运行一次发布命令，不需要先单独生成 PAK，也不需要先单独构建安装器。发布脚本仍会为保证包内组件一致而重新生成这两项。

### 4. 生成官方文本查询文件

维护者从 [repak Releases](https://github.com/trumank/repak/releases) 准备 `repak 0.2.3`，从 [UAssetGUI Releases](https://github.com/atenfyr/UAssetGUI/releases) 准备 `UAssetGUI 1.1.0`，并安装 Python 3。工具放在开发者自己的工具目录或加入 `PATH`，不复制进仓库。然后从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_official_texts\build.ps1 `
  -GameRoot "<Steam common 下的 Octopath_Traveler2 目录>" `
  -RepakPath "<repak 0.2.3 的 repak.exe>" `
  -UAssetGuiPath "<UAssetGUI 1.1.0 的 UAssetGUI-v1.1.0.exe>"
```

脚本从目标 build 的 `TalkData_JA`、`EN`、`IT`、`FR`、`DE`、`ES`、`ZH_TW`、`ZH_CN` 与 `KR` 生成对应的 `official_*.tsv`，临时解包内容只进入 `temp/official-texts/`，成功后直接更新 `mod/Scripts/`。这九个生成文件被 Git 忽略，只进入最终发布包，不在用户安装时生成。

### 5. 生成日语与英语解析数据

日语和英语分别使用 `scripts/analysis/ja/` 与 `scripts/analysis/en/`，每套数据集都有自己的 `input/`、`results/` 和 `manifest.json`。输入由对应官方文本与简体中文官方文本生成：

```powershell
python scripts\analysis\tools\dataset.py export `
  --language ja `
  --source mod\Scripts\official_ja.tsv `
  --zh-cn mod\Scripts\official_zh_cn.tsv `
  --output-dir scripts\analysis\ja

python scripts\analysis\tools\dataset.py export `
  --language en `
  --source mod\Scripts\official_en.tsv `
  --zh-cn mod\Scripts\official_zh_cn.tsv `
  --output-dir scripts\analysis\en
```

日语结果使用 `reading`，英语结果使用 IPA 字段 `pronunciation`；完整 JSONL 约束和 Agent 指令只维护在 `scripts/analysis/tools/README.md`。Agent 把结果写入对应语言的 `results/`，工具根据 manifest 中的语言选择结果结构。输入、结果和 manifest 都保持 Git 忽略。

解析过程中可以分别查看和校验两套数据：

```powershell
python scripts\analysis\tools\analysis_viewer.py --language ja --batch 0001
python scripts\analysis\tools\analysis_viewer.py --language en --batch 0001

python scripts\analysis\tools\dataset.py validate --dataset-dir scripts\analysis\ja
python scripts\analysis\tools\dataset.py validate --dataset-dir scripts\analysis\en
```

所有日语批次完成后生成当前发布运行时使用的查询表：

```powershell
python scripts\analysis\tools\dataset.py validate `
  --dataset-dir scripts\analysis\ja `
  --require-complete

python scripts\analysis\tools\dataset.py build-runtime `
  --dataset-dir scripts\analysis\ja `
  --output mod\Scripts\analysis_ja.tsv `
  --require-complete
```

`build-runtime` 同样能把英语数据集合并为带 `EN` 标识的 `analysis_en.tsv`，但当前游戏运行时和发布包仍只消费日语查询表。要在新开发机重建任一数据集，需要先恢复该开发者自己的对应语言工作区。

### 6. 更新覆盖 PAK

当前覆盖 PAK 只包含以下四个虚拟文件：

```text
Octopath_Traveler2/Content/UserInterface/Option/BP/OptionMenuWBP.uasset
Octopath_Traveler2/Content/UserInterface/Option/BP/OptionMenuWBP.uexp
Octopath_Traveler2/Content/UserInterface/Common/Font/PC_Font/FONT_MJ_CN_WeiBei_PC.uasset
Octopath_Traveler2/Content/UserInterface/Common/Font/PC_Font/FONT_MJ_CN_WeiBei_PC.uexp
```

这四个文件的当前发布源位于 `scripts/build_pak/source/`，并保持相同的虚拟目录。更新它们时使用 repak 0.2.3 从游戏主 PAK 抽取原文件到 `temp/pak-edit/`，以 UAssetGUI 1.1.0 和 `VER_UE4_27` 打开并保存，确认 `.uasset` 与配套 `.uexp` 同步后，再替换 `scripts/build_pak/source/` 中对应文件。`OptionMenuWBP` 负责注册设置分类，`FONT_MJ_CN_WeiBei_PC` 负责解析面板的中日文字形回退；具体已确认改动见 `docs/research.md`。

从仓库根目录生成 PAK：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_pak\build.ps1 `
  -RepakPath "<repak 0.2.3 的 repak.exe>"
```

也可以把 `repak.exe` 加入 `PATH` 或设置 `REPAK_PATH` 后省略参数。脚本固定使用 UE4 V11、Zlib、mount point `../../../` 和 path hash seed `836401085`，校验源目录与生成 PAK 都只有上述四项，然后写入 Git 忽略的 `mod/pak/OctopathDialogueAssistant_P.pak`。

### 7. 准备 UE4SS 与图形安装器

UE4SS 运行包不进入 Git。以下命令从 `scripts/common.ps1` 固定的上游 URL 下载 UE4SS 3.0.1，校验 SHA256 后写入 `mod/runtime/UE4SS/3.0.1/`；文件已经存在且哈希一致时直接复用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\fetch-ue4ss.ps1
```

图形安装器是 `scripts/install.ps1` 与 `scripts/uninstall.ps1` 的 WinForms 前端，本身不内嵌运行数据。修改安装器界面或启动逻辑后，从仓库根目录重新构建：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\installer\build.ps1
```

构建结果固定为 Git 忽略的根目录 `OctopathDialogueAssistantInstaller.exe`。

### 8. 安装与针对性验证

完成 TSV、PAK、UE4SS 和安装器准备后，退出游戏，可用图形安装器选择游戏目录并执行安装，也可以直接安装当前工作区：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 `
  -GameRoot "<Steam common 下的 Octopath_Traveler2 目录>"
```

安装器只复制工作区中的 UE4SS、Lua、配置、覆盖 PAK、九种官方文本和日语解析数据。启动游戏后只验证本次改动涉及的流程；运行时问题查看游戏 `Binaries/Win64/UE4SS.log`。常规开发不执行安装、卸载、重装往返测试，也不生成验证记录、补丁副本或测试制品。

### 9. 一键生成发布包

正式打包前，确保九种 `official_*.tsv` 和完整的 `analysis_ja.tsv` 已按前述步骤生成。repak 已加入 `PATH` 或设置 `REPAK_PATH` 时，从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1 -Version "1.0.0"
```

也可以用 `-RepakPath "<repak.exe>"` 指定一次性路径。省略 `-Version` 时，脚本优先使用当前提交的精确 Git tag；当前提交没有 tag 时使用 `<短提交号>-dev`。

脚本按顺序执行：

1. 从 `scripts/build_pak/source/` 重新生成覆盖 PAK；
2. 下载或复用并校验固定版本 UE4SS；
3. 从 C# 源码重新编译图形安装器；
4. 检查九种官方文本 TSV、日语解析 TSV 以及全部安装输入；
5. 只把玩家安装所需文件汇集到临时目录；
6. 输出 `dist/OctopathDialogueAssistant-<版本>.zip`，并在控制台打印 SHA256；临时目录随构建结束清理。

发布 ZIP 根目录固定包含：

```text
OctopathDialogueAssistantInstaller.exe
README.md
README.en.md
assets/*
scripts/common.ps1
scripts/install.ps1
scripts/uninstall.ps1
mod/Scripts/main.lua
mod/Scripts/config.lua
mod/Scripts/official_*.tsv
mod/Scripts/analysis_ja.tsv
mod/pak/OctopathDialogueAssistant_P.pak
mod/runtime/UE4SS-settings.ini
mod/runtime/UE4SS/3.0.1/UE4SS_v3.0.1.zip
```

`scripts/build_official_texts/`、`scripts/analysis/`、`scripts/build_pak/`、`scripts/installer/`、`docs/` 和 `.git` 都属于开发内容，不进入玩家安装包。将 `dist/` 中的 ZIP 作为 GitHub Release 资产上传；GitHub 自动生成的 Source code ZIP 只是源码快照，不作为安装包。

### 10. 提交边界

提交或打包前确认：

- `scripts/build_pak/source/`、`mod/Scripts/main.lua`、`mod/Scripts/config.lua`、构建脚本和文档进入版本控制；
- `official_*.tsv`、`analysis_ja.tsv`、生成 PAK、UE4SS 下载包、安装器 EXE、`dist/` 与 `temp/` 未进入版本控制；
- `scripts/analysis/ja/`、`scripts/analysis/en/` 中的输入、结果与 manifest、日志和查看器缓存未进入版本控制；
- `README.md` 与 `README.en.md` 只反映使用者可见的当前行为，本文与 `docs/research.md` 反映对应实现和已确认对象。

## RichEvent 重放

主线与旅行记录中的主要演出使用 LevelSequence。Mod 在 `TalkText`/`TalkVoice` 触发时记录当前 Sequence Player 和帧位置，把相邻两次台词触发之间定义为一个句子片段。

当前实现使用 `JumpToSeconds` 定位到目标台词暂停帧，恢复镜头和角色时间轴状态；文本和语音由活动 `TalkText` 原地重置。每句只绑定唯一变化的 RichEvent Player。

运行时捕获入口是 `TalkText_C:PlayVoice`。`EventManagerBP_C:StartTalk` 和每帧执行的 `EventManagerBP_C:UpdateTalk` 都返回控制原生流程的布尔结果，因此不进入 Lua hook 链；普通对话的完成、活动 UI 栈退出和玩家控制恢复完全保留给游戏。

## 运行时状态

```text
LineRecord
├── DrawTexts / VoiceLabel 副本
├── 说话人文本与可见性
├── BalloonParam 目标角色 / 方向 / 尾巴 / 偏移 / 类型 / 姓名
├── TalkText / Balloon 运行时引用
├── RichEvent Sequence Player 与资源路径
├── 暂停帧 / 子帧 / 帧率
└── 捕获时间
```

运行时只保留一个小型环形队列，不持久化到存档。

当前实现保留最近 12 个 `LineRecord`。手动调用 `StartAnimation` 引发的 `PlayVoice` 会由一次性标记识别并跳过采集，因此不会把同一句追加为新历史；正常推进到已经记录的下一句时会更新该记录并恢复对应历史位置。

`LiveDialogue` 始终指向游戏当前正在使用的原生 `TalkText` 与父级 `Balloon`。每条 `LineRecord` 另外保存以下值的独立副本：

- `DrawTexts` 中保留显式换行的原始字符串；
- `VoiceLabel` 中的 `FName`；
- 说话人文本与相关控件可见性；
- `BalloonParam.TargetActor`、方向、尾巴、偏移、文本类型与姓名 `FName`；
- RichEvent Player、资源、暂停帧与帧率。

重放时先 Jump 到目标暂停帧，再把保存值写回 `LiveDialogue` 的同长度数组和当前 `BalloonParam`。重建顺序为：恢复目标角色与气泡参数 → 恢复姓名/类型 → `TextIndex = 0` → `InitAnim` → `InitSize` → `SetupBalloonTair` → 再次恢复姓名 → `UpdateTranslation` → `StartAnimation`。`StartAnimation` 调用游戏自己的 `PlayVoice`，文本、姓名、气泡和语音均在活动原生对象上更新。

运行输入由 UE4SS 注册为可配置的无修饰字母键，默认 `R` 重播本句、`G` 回到上一句、`T` 显示或隐藏官方翻译、`V` 显示或隐藏解析。四个快捷键共享同一配置与冲突交换逻辑；解析与翻译共用开关，不依赖所选翻译语言。分析语言拥有独立设置，目前只有日语对应运行时数据，其他选项不会注册为可用的解析动作。

第一句进入历史时，Mod 取得活动 `UIEventSkip_C` 的 WidgetTree，把已开启功能对应的 `MenuGuideItem_C` 直接加入其根 `CanvasPanel` 或 `Overlay`，按各自右边界锚定到画面右上角，并根据标签实际宽度分别设置偏移，使相邻说明文字与下一枚键帽之间保持一致的视觉间距。`GuideText_00` 使用 `FONT_KS_NewCinema_PC`，`ButtonText` 使用 `FONT_KS_Meldir_PC`。字母经 `KeyConfigButton1WBP_C.UpdateText` 和 `LibText.ConvFontImageText` 转换为本作键帽字形，再写入 `ButtonText`。提示继承剧情控制层的原生可见性，不跟随气泡位置。

## 官方翻译显示

发布前的数据构建从已确认游戏 build 的主 PAK 读取 `TalkData_JA`、`EN`、`IT`、`FR`、`DE`、`ES`、`ZH_TW`、`ZH_CN` 与 `KR`，只提取每行的原生行名和 `Text` 数组，分别生成 UTF-8 只读查询文件。安装器直接复制这些发布数据；运行时第一次显示某种语言时延迟加载对应文件，当前 `LineRecord.VoiceLabel` 作为行键，`TextIndex` 选择对应文本槽位。数据来自游戏官方文本表，不经过模型或翻译服务。

翻译开启后，Mod 使用游戏已有的 `HelpWindowWBP_C`。创建实例前，Lua 临时把该 Blueprint 的 `HelpText` 模板设为 `DisableRefreshFont = true`、所选 `EKSLanguage`、`EKSFontType::Talk` 和该语言的原生 PC 对话字体，让新实例在建立 Slate 文本控件时直接复制正确字库，并阻止该控件按当前界面语言重新选择字体；实例建立后立即恢复原模板，不影响游戏随后创建的帮助框。Mod 同时把相同字段写入新实例，再将其挂入 `UIEventSkip_C` 根节点并重新写入文本。控件保留原生 `BG_Root` / `BodyRootBorder` 背景，把内部文本宽度扩展到右上角区域，解除原帮助框约两行的高度上限，并隐藏滚动条，使背景按完整台词高度增长。每次正常推进、重播本句或回到历史句时只刷新文本；再次按翻译快捷键会移除该控件。剧情控制层销毁时控件随其 WidgetTree 一起退出。

## 日语解析显示

线下结果只保留词汇与语法两类信息，并按 `row_name + text_index` 合并为 UTF-8 的 `analysis_ja.tsv`。运行时第一次按解析键时延迟加载，并以当前 `LineRecord.VoiceLabel + TextIndex` 精确查询；未完成解析的台词显示暂无解析，不会回退到同一行的其他文本槽位。游戏运行过程中没有模型调用或网络请求。

解析面板同样使用 `HelpWindowWBP_C`，固定锚定在画面左下角。其复合字体以游戏的简体中文对话字体为默认字形，并把简体字库缺少、日文字库具备的原文字符路由到日文对话字体，因此简体中文说明与 `違う` 等日文原词可以在同一个文本控件中完整显示。解析与翻译共用功能开关；只有独立快捷键，不增加第二个开关。所选翻译语言只决定官方翻译面板的数据和字体，不参与解析功能的可用性判断；独立分析语言决定解析数据集，目前仅 `JA` 可用。推进、重播或切换历史句时，可见的解析面板随当前记录刷新。

## Mod 配置 UI

- 独立覆盖 PAK 在 `OptionMenuWBP_C:InitCategoryTab` 中向 `ListWidgetCategory` 追加索引 `6`；新增分类项复用游戏设置页的通用分类图标，再由原生 `AddCategoryTab` 建立分类按钮。该 PAK 同时覆盖 `FONT_MJ_CN_WeiBei_PC` 的复合字体定义，只增加缺失日文字符到原生日文字体的映射，不包含或替换游戏字体文件。
- PAK 只在 `InitCategoryTab` 中注册索引 `6`，其右侧内容和输入结果由运行时建立。
- Lua 不读取或改写 `CategoryWidgetList`，也不在设置页打开、建立分类或空闲期间轮询 Option 对象；只有玩家完成分类切换后，`ChangeCategory` 回调才判断当前索引。
- `ChangeCategory`、`MoveCursor`、`OnDecideOption`、`SendLRToExWidget` 和 `OnCancel` 共同接入原生分类切换、列表光标、确认、左右调整与返回流程。
- 进入 Mod 分类时，游戏先清空索引 `6` 的列表；Lua 随后创建八个 `ListItemWidget_Opt1_C` 并加入 `OptItemVerticalBox`，不读写游戏的 `OptionItemList`。每行标题只挂载从 `MenuGuideItem_C` 取得的 `GuideText_00`；重播与翻译开关分别把 `ToggleButtonWBP_C` 收束为一个带勾选图标的 `ON` / `OFF` 状态项；四个按键项只挂载 `KeyConfigButton1WBP_C` 转换后的键帽文字控件，并以相同的右对齐槽位显示；翻译语言与分析语言分别使用独立的游戏原生 `LanguageButtonWBP_C`。
- 分类索引 `6` 没有游戏内置的标题贴图和本地化说明资源；活动期间折叠 `TitleImage`，并使用 `MenuFooter.SetHelpText` 显示与当前行对应的 Mod 说明。离开分类时恢复原可见性，目标分类由游戏自己的 `UpdateOptionMenuItem` 建立。
- 八行由 Mod 分类自己的状态表维护光标、高亮和确认。分类刚切入时全部保持失焦；第一次 `OnDecideOption` 只进入内容区并聚焦第一行，随后 `MoveCursor` 才在可用行之间移动，确认或左右输入才修改设置。`OnCancel` 返回分类栏时全部再次失焦，使左侧分类光标与内容光标互斥。
- 关闭重播开关时，两项重播按键行禁用并置灰；关闭翻译开关时，下面四项翻译与解析设置全部禁用并置灰。翻译开启时两个语言项始终可选；分析语言不是 `JA` 时，仅解析按键行禁用并置灰。光标移动会跳过不可用行，条件恢复后重新接受输入。
- 确认按键条目后进入字母捕获；捕获提示只显示在页脚，不改变行标题或键帽位置。四个快捷键保持唯一，选择另一功能正在使用的字母时，两项自动交换。
- 两个语言列表都与游戏 `Text Language` 的九项顺序一致。各自的 `LanguageButtonWBP_C` 建立九种原生本地化名称、左右箭头和选中显示；Lua 分别保存翻译语言与分析语言，不读取或修改游戏当前文本语言。
- 切换到其他分类后，游戏已先销毁 Mod 行；Lua 只清除对象引用并恢复菜单自有标题区域，不再调用旧行控件。
- 所有新增控件都由 `WidgetBlueprintLibrary.Create` 创建并挂入现有 WidgetTree，不动态构造 UMG 类型或容器。
- `config.lua` 位于 Mod 的 `Scripts` 目录，保存重播开关、两个重播键、翻译开关、翻译语言、翻译键、分析语言与解析键。

## 安全约束

- 不修改 EXE、主 PAK 或存档；设置页扩展位于独立的覆盖 PAK。
- 不通过 `EventIndex - 1` 回退剧情解释器。
- 原地重放使用 Jump 定位目标帧，目标范围内的 Event Track 不参与执行。
- 热键只在同一 RichEvent 的暂停点、活动对话对象有效且保存数组与活动数组同形时响应。
- 所有 UObject 调用通过 `ExecuteInGameThread` 执行。
- 数组形状或活动对象不匹配时不改动当前对话；任何原地准备步骤报错都会恢复进入该步骤前的文本、语音标签、气泡参数、说话人和 Sequence 位置。

## 安装器行为与卸载

- `OctopathDialogueAssistantInstaller.exe` 只负责选择游戏目录、调用相邻 `scripts/` 中的安装或卸载脚本，并在窗口中显示脚本输出；发布时必须与仓库中的 `mod/`、`scripts/` 一起提供。
- 安装器只支持已确认的主程序 SHA256，并固定使用 UE4SS 3.0.1 的压缩包与 DLL 哈希。
- 固定版本的 UE4SS 安装包与运行配置存放在 `mod/runtime/`；九种官方文本查询文件与日语解析文件随运行时代码存放在 `mod/Scripts/`。
- `scripts/build_official_texts/build.ps1` 使用 `repak`、`UAssetGUI` 和 Python 完成发布前的数据构建，具体命令见 `scripts/build_official_texts/README.md`；这些工具不属于用户安装包或安装流程。安装器只校验并复制仓库内已经生成的运行文件。
- UE4SS、运行时配置、Lua、九种官方文本查询文件、日语解析查询文件、`mods.txt` 与独立 Mod PAK 都按文件记录 `added`、`modified` 或 `existing` 操作；修改前内容保存到游戏 `Win64` 下的独立备份目录。
- `config.lua` 记录为可变的 `user_config`：安装更新不按源文件哈希覆盖用户值，卸载时随 Mod 删除。
- 游戏 EXE 与主 PAK 仅作为受保护对象记录，不参与复制或修改。
- `uninstall.ps1` 根据 Mod 内的最小安装状态执行卸载：新增文件删除、修改文件按哈希恢复、既有文件保留；任何安装后哈希漂移都会中止对应操作。
- 安装脚本和 Lua 均不解析或访问 `SaveGames`。
