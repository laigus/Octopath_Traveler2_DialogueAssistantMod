# 官方文本查询文件构建

本目录只负责在发布前从受支持的游戏 build 生成九种语言的剧情台词与“打听/调查”人物资料官方文本查询文件，不参与解析、Mod 安装或 Mod 运行时。

## 依赖

- `repak 0.2.3`
- `UAssetGUI 1.1.0`
- Python 3

这些工具由维护者在构建时提供，不进入用户安装包。

## 生成

从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_official_texts\build.ps1 `
  -GameRoot "<Steam common 下的 Octopath_Traveler2 目录>" `
  -RepakPath "<repak 0.2.3 的 repak.exe>" `
  -UAssetGuiPath "<UAssetGUI 1.1.0 的 UAssetGUI-v1.1.0.exe>"
```

脚本会校验游戏主程序、游戏主 PAK 和两个构建工具的固定哈希，仅在项目 `temp/official-texts/` 中保存临时提取文件。它从九种 `TalkData_*` 生成剧情查询文件，并结合 `NPCHearData.HistoryTextID` 与九种 `GameText*` 生成已解锁人物资料的查询文件。成功后更新：

```text
mod/Scripts/official_ja.tsv
mod/Scripts/official_en.tsv
mod/Scripts/official_it.tsv
mod/Scripts/official_fr.tsv
mod/Scripts/official_de.tsv
mod/Scripts/official_es.tsv
mod/Scripts/official_zh_tw.tsv
mod/Scripts/official_zh_cn.tsv
mod/Scripts/official_kr.tsv
mod/Scripts/official_field_ja.tsv
mod/Scripts/official_field_en.tsv
mod/Scripts/official_field_it.tsv
mod/Scripts/official_field_fr.tsv
mod/Scripts/official_field_de.tsv
mod/Scripts/official_field_es.tsv
mod/Scripts/official_field_zh_tw.tsv
mod/Scripts/official_field_zh_cn.tsv
mod/Scripts/official_field_kr.tsv
```

`official_*.tsv` 以 `row_name + text_index` 为键保存剧情台词；`official_field_*.tsv` 以 `HistoryTextID` 为键保存人物资料。十八个生成结果受 `.gitignore` 排除，只作为发布包运行时数据，由 `scripts/install.ps1` 直接复制。
