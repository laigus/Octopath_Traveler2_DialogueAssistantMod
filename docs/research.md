# 本机游戏对象研究记录

分析对象：Steam build `13399590`，Unreal Engine `4.27.2`。

## RichEvent / LevelSequence

- 主线与旅行记录演出资源包含 Camera Cut、角色 Transform、动画、事件、`TalkText` 和 `TalkVoice` 轨道。
- 活动剧情播放器是 Persistent Level 下的 `LevelSequencePlayer`，资源路径位于 `/Game/Event/RichEvent/`。
- 相邻两句之间唯一改变当前帧、资源路径属于 RichEvent 且状态为暂停的 Player，可绑定到对应台词；新建 Player 的第一条快照没有同名旧对象，必须单独纳入候选。
- 本机日志中，`TX_MS_SIN_3B_1200_0010_EX1` 出现时播放器总数由 `9` 增为 `10`，下一句 `EX2` 的快照显示新增的 `RI_MS_SIN_3B_1200` Player 从首句的 `140` 帧推进至 `170` 帧。世界地图 UI 播放器同时变化，但资源不属于 RichEvent，须排除。
- 已确认的剧情资源 `/Game/Event/RichEvent/01_Main/50_SHO/EX3/RI_MS_SHO_EX3_0600` 使用 `30/1` 帧率；相邻台词暂停帧为 `80` 与 `120`，播放器状态值为 `5`。
- 每条记录保存 Player 引用、Sequence 资源路径、帧、子帧、帧率和起止范围。

## `TalkText_C`

- `VoiceLabel`
- `PlayVoice`
- `RequestPlayVoiceByLabel`
- `StopVoice`
- `OriginText`
- `DrawTexts`
- `TextIndex`
- `InitAnim`
- `StartAnimation`

`InitAnim` 根据 `DrawTexts[TextIndex]` 重建原始文字、逐字显示计数和富文本状态。`StartAnimation` 启动文字动画并调用当前对象的 `PlayVoice`。

UE4SS 侧把 `DrawTexts` 和 `VoiceLabel` 展开为独立元素副本。重放时只在活动数组长度与记录一致时逐元素写回，保留显式换行和语音标签。

## `EventManagerBP_C`

- `StartTalk` 返回布尔结果。
- `UpdateTalk(DeltaTime)` 每帧调用原生气泡系统并返回布尔结果；该结果参与对话完成判断。
- `UpdateTalk` 还检查活动 UI 栈，并在活动对象不是当前 `BalloonBundle` 时重新压入对话对象。

运行时不在 `StartTalk` 或 `UpdateTalk` 上注册 Lua hook。台词观察使用 `TalkText_C:PlayVoice`，气泡关闭动画结束的无返回值回调只清理 Mod 控件；原生对话完成判定和玩家控制恢复路径不由 Mod 改写。

固定版本 UE4SS 3.0.1 存在原生 Blueprint 函数库挂钩缺陷，上游 [issue #467](https://github.com/UE4SS-RE/RE-UE4SS/issues/467) 记录了 UE4.27 下的 `UFunction::FuncPtr hook` / `no function map entry` 异常。本机同一异常后出现 `FMallocBinned2` 未识别内存块断言。因此运行时只注册 `/Game/` Blueprint 回调，不挂钩 `KSTextStatics:GetTalkText` 等原生函数库函数。

## `Balloon_00_C`

- `BalloonParam.Text.Names`
- `BalloonParam.TargetActor`
- `BalloonDir`
- `EnableTail`
- `OffsetParam`
- `InitSize`
- `SetupBalloonTair`
- `UpdateTranslation`
- `CurrentPlayVoice`

气泡尺寸由 `InitSize` 根据当前文本计算，尾巴布局由 `SetupBalloonTair` 更新，位置由 `TargetActor`、方向与偏移参数共同决定。重放记录同时保存这些字段，并在 `UpdateTranslation` 前恢复。

## 无边框独白字幕（DeepThink）

- `/Game/UserInterface/Balloon/BP/Balloon_DeepThink` 与 `Balloon_DeepThinkTextFixed` 均直接继承原生 `BalloonBase`，不是 `Balloon_00_C` 的子类，没有普通气泡专用的 `InitSize`、`SetupBalloonTair` 和 `SetTypeImageFromTalkChara`。正文 `TalkText_DeepThink_C` 继承 `TalkText_C`，共享 `DrawTexts`、`VoiceLabel`、`TextIndex` 和 `StartAnimation → PlayVoice`。
- `Balloon_DeepThink_C.UpdateTranslation` 读取 `BalloonParam.TargetActor/Offset/BalloonDir`、自身 `Offset` 和文字尺寸，调用 `TalkText_DeepThink.UpdatePosition` 更新 `CanvasPanel_50` 的槽位置。`Balloon_DeepThinkTextFixed_C.SetPosition(Type)` 把正文移到上/中/下 Canvas，写入 `TextPos`，并按文字尺寸居中。
- `TalkText_C.InitTextSize` 维护 `TextBlockSize` 和正文 Canvas 槽尺寸；独白快照复制正文、`CanvasPanel_50`、`RefTextBlock`、`RefRichTextBlock` 中有效 Canvas 槽的尺寸、位置与对齐，避免回看不同长度的台词时沿用当前句尺寸。`InitAnim` 按原始 `TextIndex` 重建文本与富文本状态。
- 两类独白开场动画结束后均设置局部 `Sequence = 2` 并调用正文 `StartAnimation`。关闭后设置 `EndFlag = true`、隐藏窗口并清空完成委托；Mod 只观察 `Balloon_DeepThink_C:WidgetAnimationEvt_Close_K2Node_WidgetAnimationEvent_1` 与 `Balloon_DeepThinkTextFixed_C:CloseAnimationFinish`，不调用这些关闭动作，也不挂钩返回布尔值的 `Init`、`CallNext`、`CloseBalloon`。
- 截图台词为 `TX_MS_KUS_2M_0100_0020`。`/Game/Event/RichEvent/01_Main/30_KUS/ep2_M/RI_MS_KUS_2M_01A0` 与 `01B0` 的 SequenceDirector 均通过 `BalloonOpenLabel` 显示 `0010/0020/0030` 等台词；此类居中字幕属于 RichEvent 演出，不是 `NarrationWidget_C` 的整页旁白。

## 原地重放顺序

1. 校验活动 RichEvent Player、暂停状态、Sequence 资源和数组形状。
2. 保存活动对话与 Sequence 位置。
3. Jump 到目标句暂停帧。
4. 写回文本、语音标签、姓名、目标角色与气泡参数。
5. 恢复记录的原始 `TextIndex` 并执行 `InitAnim`；普通气泡使用 `InitSize`、`SetupBalloonTair` 和位置更新，独白使用自己的 Canvas 布局和位置更新。
6. 调用 `StartAnimation` 播放文字动画与原声。

运行时保留最近 12 条 `LineRecord`。手动重放触发的 `PlayVoice` 由一次性标记识别，历史索引保持在目标句；正常剧情推进会更新对应记录。

## 输入与原生 UI

- build `13399590` 的默认输入表中，`G` 未绑定 Action/Axis；Mod 默认使用 `R` 重播本句、`G` 回到上一句。
- `MenuGuideItem_C` 的 `ButtonText` 使用 `FONT_KS_Meldir_PC`，`GuideText_00` 使用 `FONT_KS_NewCinema_PC`，布局为键帽加说明文字。
- `KeyConfigButton1WBP_C.UpdateText` 调用 `LibText.ConvFontImageText`，把键名转换为键帽字体字符。
- `UIEventSkip_C` 是剧情中的播放控制层，其根控件为 `Overlay`。Mod 把当前可用功能对应的 `MenuGuideItem_C` 直接加入根节点，并按各标签的实际宽度使用互不相交的右侧 Padding，使相邻说明文字到下一枚键帽的视觉间距一致；提示固定在画面坐标并继承剧情层可见性。
- `/Game/Talk/Database/` 中存在与原生 Text Language 列表一致的九张表：`TalkData_JA`、`EN`、`IT`、`FR`、`DE`、`ES`、`ZH_TW`、`ZH_CN` 和 `KR`。它们使用相同的 `TalkText` 行结构并共享行名，文本位于该行的 `Text` 数组。活动 `TalkText_C.VoiceLabel` 来自独立的语音表，不保证等于文本行名。
- `TalkVoice_JA` 中，文本行 `TX_MS_KAR_2B_0200_0250` 的 `Voice[0]` 是 `TX_MS_KAR_2B_0200_0250_B`，文本行 `TX_MS_KAR_2B_0200_0280` 的 `Voice[0]` 是 `TX_MS_KAR_2B_0200_0280_A`。前者也由运行日志确认。两行原文、官方简中与解析均存在于当前查询表；第 0250 批 input/results 使用不带后缀的文本编号。对照当前日文文本行，语音表中有 295 个非空语音槽位的语音名不同于文本行名，其中 111 个语音名又是其他文本行的名称；仅检查语音名是否存在于文本表仍不足以识别原文。
- PC 对话字体表把日语映射到 `FONT_KS_NewCinema_PC`，英语及四种欧洲语言映射到 `FONT_KS_Skech_PC`，繁体中文映射到 `FONT_MJ_TW_FangSong_PC`，简体中文映射到 `FONT_MJ_CN_WeiBei_PC`，韩语映射到 `FONT_KR_YDHopeL_PC`。
- `HelpWindowWBP_C` 自带 `BG_Root`、`BodyRootBorder` 和自动换行；其中 `HelpText` 是 `KSTextBlock`。原控件的 `TextSizeBox.MaxDesiredHeight = 54.5` 与 `SizeBox_Clipping.MaxDesiredHeight = 53.5` 只容纳约两行，并由 `TextScrollBox` 显示滚动条。Mod 把文本宽度设为 `500`、换行宽度设为 `480`，把两层高度上限放宽到 `800`，隐藏滚动条并让外层 Canvas 槽使用 AutoSize，因此法语等较长官方台词会连同背景完整展开。该类默认会按全局界面语言刷新字体；Mod 在创建实例前临时设置 Blueprint 的 `WidgetTree.HelpText.DisableRefreshFont = true`，并写入所选 `EKSLanguage`、`EKSFontType::Talk` 和对应 PC 对话字体，使实例从首次构造起使用目标语言字库，随后立即恢复模板。
- 解析结果以文本 `row_name` 和原始 `TextIndex` 建立独立索引；解析面板复用 `HelpWindowWBP_C` 并固定在左下角。原始 `FONT_MJ_CN_WeiBei_PC` 的默认字库缺少部分日文汉字，例如 `違`；Mod PAK 为该复合字体补充精确字符范围并引用游戏已有的 `KS_NewCinema_Std_D` 字体面，因此简体中文说明和日文原词可以混排。解析与翻译共用开关但使用独立的分析语言设置，目前只有日语解析数据。
- `OptionMenuWBP_C` 的分类系统由 `InitCategoryTab`、`AddCategoryTab`、`AddCategoryPart`、`CategoryBox`、`CategoryWidgetList` 和 `CategoryCursorPos` 组成；`ChangeCategory` 会按 `CategoryWidgetList` 的最后索引循环切换。
- Mod PAK 在 `InitCategoryTab` 原有结构体数组建立完成后追加分类 ID `6`，继续交给原生 `AddCategoryTab` 生成第七个分类按钮；UE4SS Lua 侧不读取、构造或传递该原生分类结构体。
- `UpdateOptionMenuItem(Index)` 负责清理并建立右侧选项列表；具体选项行加入 `OptItemVerticalBox`，`OptItemScrollBox` 只是它的滚动容器。索引 `6` 的原生列表为空，Lua 在 `ChangeCategory` 完成后独立创建八条 `ListItemWidget_Opt1_C`。
- `Refresh Title Icon` 与 `GetCategoryDescriptionText` 只定义索引 `0..5`；Mod 分类活动期间折叠缺失的标题贴图，并通过 `MenuFooter.SetHelpText` 持续提供当前选项的说明。
- 分类确认与内容确认都会经过 `OnDecideOption`：Mod 分类第一次收到该回调时只从分类导航进入内容区，后续回调才确认当前设置项。内容区上下移动走 `MoveCursor`，左右输入走 `SendLRToExWidget`，返回走 `OnCancel`；这些回调只在内容区聚焦期间处理八行。Mod 分类使用 `ListItemWidget_Opt1_C` 选项行、独立的 `GuideText_00` 行标题、收束为单一状态的 `ToggleButtonWBP_C`、`KeyConfigButton1WBP_C`、两个 `LanguageButtonWBP_C` 和状态表完成交互，不修改 `OptionItemList`。按键项从 `KeyConfigButton1WBP_C` 中取出已转换的 `Text` 键帽控件，使用一致的 Fill、右对齐、垂直居中槽位；两个原生语言控件分别建立九项本地化名称，`SetIndex`、`InputLeft` 与 `InputRight` 管理各自的选择显示。
- 运行时 UI 只创建 Blueprint UserWidget，不构造原生 `Border`、`VerticalBox` 或 `HorizontalBox`。

## 打听与调查资料界面

- 药师的“打听”界面由 `FieldCommandWidgetHear_C` 管理，学者的“调查”界面由 `FieldCommandWidgetSearch_C` 管理；两者都使用名为 `SearchDetail` 的 `SearchDetailPartsWidget_C` 子控件显示人物资料。
- `SearchDetailPartsWidget_C:SetupSearchDetail(NPCLabel, IsAlreadyCompleted)` 根据 `NPCLabel` 读取 `NPCHearData`，取得其中的 `HistoryTextID`，再通过游戏文本接口把资料写入 `HistoryText`。`ChangeLanguageProc` 使用同一条读取链路刷新资料文本。
- `FieldCommandWidgetHear_C` 与 `FieldCommandWidgetSearch_C` 的 `OpenInfoDialog` 均调用 `SetupSearchDetail(NPCLabel, false)`。`SetupSearchDetail` 无条件填充人物正文，`IsAlreadyCompleted` 仅参与情报物品说明的分支；首次取得资料也应捕获正文。
- UE4SS 3.0.1 的 [RegisterHook](https://docs.ue4ss.com/release/lua-api/global-functions/registerhook.html) 对 `/Game/` Blueprint 函数使用第二参数作为执行后回调，忽略第三参数。`SetupSearchDetail` 使用该形式；两种父界面的 `Close(IsNotCloseWidget)` 也是 Blueprint 函数，将状态置为关闭流程，关闭回调负责清理 Mod 资料引用与控件。
- `NPCHearData` 位于 `/Game/Character/Database/NPCHearData`，共 1859 行；人物资料键保存在 `HistoryTextID` 字段。九种官方文本位于 `/Game/GameText/Database/GameTextJA`、`EN`、`IT`、`FR`、`DE`、`ES`、`ZH_TW`、`ZH_CN` 和 `KR`，同一 `HistoryTextID` 可用于查询对应语言文本。
- 图中人物资料对应 `NPCHearData` 行 `FC_INFO_NPC_Twn_Snw_2_1_A_TALK_0700`，其 `HistoryTextID` 为 `PRF_NP_Twn_Snw_2_1_A_TALK_0700`；日文与官方简体中文均能通过该键准确匹配。
- `SearchDetailPartsWidget_C` 的根控件是 `Overlay`，可沿用现有原生帮助窗创建、字体切换和定位逻辑承载翻译与解析面板。

## 队友旅途对话（Party Chat）

- `/Game/UserInterface/PartyChat/Database/PartyChat` 有 195 条资料，包含 `EventLabel`、`RequiredCharacter` 等字段。显示界面是 `/Game/UserInterface/PartyChat/BP/PartyChat.PartyChat_C`，继承原生 `PartyChatBase`，根控件为 `CanvasPanel_0`；运行时引用保存在 `EventManager.PartyChatWidget`。
- `EventManagerBP_C:StartTalkPChat` 从 `PartyChatWidget.GetCharacterPos` 取得说话人位置，将事件的 `Text`、`Dir` 和 `OptAry` 交给 `SetTalkData`，通过 `BalloonBundle.AddBalloon` 创建气泡，并调用 `FocusPartyChatCharactr` 更新角色焦点。Mod 不挂钩这个带布尔返回值的流程入口。
- 旅途记录列表为 `/Game/UserInterface/MainMenu/Record/BP/WBP_MainMenuStoryRecordPartyChat`；`EventManagerBP_C:StartPChatMode` 包含 `IsTheaterMode` 与 `PartyChatFinish` 的回放分支。角色背景 `PartyChat_C` 与 `GetBalloonBundle` 返回的气泡容器分属不同界面；翻译、解析与提示使用后者的全屏 `Overlay`，会话识别仍使用 `EventManager.PartyChatWidget`。
- `PartyChat_C:VisibleBackGround` 同时设置自身与 `CanvasPanel_0` 的可见性，并调用 `HideWidgetTemporary`；Mod 不改写此流程。背景层或面板创建成功的日志不代表新增控件已在前景气泡层显示。
- `SetTalkData` 将事件中的文本编号传给原生 `/Script/Majesty.KSTextStatics:GetTalkText(Label, OutText)`，输出为 `TalkText` 结构；其中 `Text` 字符串数组进入气泡和 `TalkText_C.DrawTexts`。语音另经 `GetTalkVoice` 查询，因此文本编号与 `VoiceLabel` 独立。
- `TalkText_C:SetText` 保存文本、语音数组并把 `TextIndex` 置零，`StartAnimation` 调用 `PlayVoice`。文本显示使用的原生气泡提供无返回值的 `Balloon_00_C:OnCloseAnimationFinished` 回调。
- 当前查询文件中 `TX_PTC_*` 与 `TX_PCJ_*` 共 3058 个文本槽位，均有对应日语解析记录；运行时以完整文本数组匹配出的编号及原始文本槽位查询，不以这两个前缀限制匹配。不同编号可能有完全相同的原文；语音标签仅在属于同文候选时辅助消歧，否则分别核对所有候选的译文和解析，显示一致结果或内容冲突提示。

## 普通 NPC 对话

- `TXT_NPC_KUS_2B_01_Twn_Snw_2_1_A_0300_001` 与 `TXT_KUS_2B_Twn_Snw_2_1_A_0300_D000_001` 的第零槽位均为截图中的“キャスティ先生のこと／さっそく領主様に知らせましたよ”。两者九种官方语言文本与日语解析逐字一致；重复编号不代表存在不同的待显示内容。
- 已有运行日志记录了 `TalkText_Balloon_C` 的普通 NPC 台词，`VoiceLabel` 是空数组，但 `DrawTexts` 和 `OriginText` 已包含完整日文；单独依赖语音标签不足以识别这类台词。
- 日志中的学者公会相关两句台词分别对应 `TX_SS_TSn21_0100_0050 + 0` 和 `TX_SS_TSn21_0100_0055 + 0`，当前官方文本与日语解析表均有对应记录。普通 NPC 台词不限定为 `TXT_NPC_*` 或 `TX_NP_*` 前缀。
- 该活动对象的外层链是 `TalkText_Balloon → WidgetTree → Balloon_03 → WidgetTree → BalloonBundleWidgetBP_C`。`/Game/UserInterface/Balloon/BP/BalloonBundleWidgetBP` 的根控件为 `Overlay_1`，类型是原生 `Overlay`，可承载固定屏幕位置的帮助窗和快捷键提示。

## 全屏旁白与说明（Narration）

- 主窗口资源为 `/Game/UserInterface/Narration/BP/NarrationWidget.NarrationWidget_C`，根节点 `Canvas` 是全屏 `CanvasPanel`，资产明确设置 `Clipping = ClipToBoundsAlways`；原生背景与装饰框槽位使用 `1280 × 720` 布局。`MessageViewList` 中的 `NarrationMessageWidget_C` 承载分段正文，`NoteWidget` 是 `NarrationNoteWidget_C`。
- 壁画截图对应 `TX_MS_KAR_2B_0100_0010` 至 `0040`。本机日志同时存在四段 `narration_ready`、提示创建和翻译/解析创建成功记录，而截图未显示 Mod 控件；数据捕获和按键触发成功不等同于实际可见。显示容器独立于该旁白画布，游戏内画面仍需验证。
- `/Game/UserInterface/Common/BP/MenuGuideItem.MenuGuideItem_C` 直接继承 `UserWidget`，根节点为 `Overlay_0`，未实现 Tick/Paint。Mod 可创建单独实例并清空其根子节点作为前景宿主；不清空旁白根节点，也不改该 Blueprint 模板。
- `PlayNarration(NarrationSetLabel)` 根据 `NarrationSetTable.LabelList` 构造 `PageText`，`NextPage` 把对应页交给 `SetPlayPageMessage`，随后递增 `PageIndex`。当前页保存在 `DrawMessageList`，段落数组为 `TextGroup`，每段的 `Text` 是官方台词编号，`None` 是留白。
- `OneLineDraw` 读取上述编号的 `TalkText.Text[0]`，再调用 `NarrationMessageWidget_C:PlayMessage`；`SettingText` 把经过换行处理的正文写入 `Message`。因此应直接复制当前页编号，而不是从已排版文字反查。
- `PlayNote(NoteLabel, UseBackground)` 读取 `TalkText.Text[0]` 并调用 `NoteWidget.SetText`，最后设置 `NoteMode = true`。它与 `PlayNarration`、`SetState`、`CloseMessage` 均无返回值；Mod 只挂钩这些 Blueprint 回调，不挂钩带布尔返回值的 `SetPlayPageMessage`、`OneLineDraw` 或 `PlayMessage`。
- `SetState` 写入枚举字段 `State`。字节码中 `1` 为开场/资源准备，`2` 为正文显示，`3` 为新页过渡，`8` 为本页显示完成；`4/5` 是换页等待，`6/7` 是结束/关闭，`9` 等待场景淡入。`Close` 先转入 `7`，关闭动画结束后转入 `0`，随后隐藏窗口。Mod 同时检查窗口层级可见性。
- `OnCursorUp`、`OnCursorDown` 及对应 Repeat 回调在原始 Blueprint 中为空事件，无输出参数。Mod 用这些回调调整自身 `HelpWindowWBP_C.TextScrollBox` 的滚动偏移；旁白窗口的确认、取消、自动翻页和完成返回值保持原样。
- 截图一对应 `TX_MS_NAR_KUS_2B_0010` 至 `0060` 六个编号，截图二对应 `TX_MS_SIN_3B_0100_0040` 至 `0080` 五个编号；各编号第零槽位均存在日语原文、官方简体中文和日语解析。

## 运行边界

- 热键要求活动对话对象有效、目标记录属于同一 RichEvent、Player 处于暂停状态且保存数组与活动数组同形。
- Sequence 使用 Jump 定位目标暂停帧；台词文本、姓名、气泡位置和语音在当前活动对象上更新。
- 所有 UObject 调用在游戏线程执行。
