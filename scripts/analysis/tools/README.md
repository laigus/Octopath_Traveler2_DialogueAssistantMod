# 台词离线解析工具

本目录只负责在游戏外导出台词、约束 Agent 输出、校验结果和浏览数据，不参与 Mod 运行时。

`dataset.py export` 从日文和简体中文官方文本表生成 Git 忽略的 `scripts\analysis/input/*.jsonl`：

```powershell
python scripts\analysis\tools\dataset.py export --ja "<official_ja.tsv>" --zh-cn "<official_zh_cn.tsv>" --output-dir scripts\analysis
```

输出清单位于 `scripts\analysis/manifest.json`，Agent 结果写入对应的 `scripts\analysis/results/NNNN.jsonl`。

## 输入

每个输入文件由 JSONL 记录组成，每行是一条独立台词：

```json
{"id":"TX_MS_SHO_EX3_0600_0010:0","row_name":"TX_MS_SHO_EX3_0600_0010","text_index":0,"ja":"わしを“雇う”……だと？","official_zh_cn":"你要“雇用”老夫……？","context_before":null,"context_after":{"ja":"何のつもりだ","official_zh_cn":"你有什么企图"},"source_hash":"0123456789ABCDEF"}
```

- `id` 和 `source_hash` 是结果必须原样返回的稳定键；源文本变化后哈希也会变化，旧结果不会被误用。
- `ja` 是唯一需要解析的目标文本。
- `official_zh_cn` 只用于消歧，不要重新翻译或改写。
- `context_before`、`context_after` 只帮助判断省略、指代和语气，不属于目标结果。

## Agent 指令

处理一个输入文件时使用以下约束：

1. 按输入顺序为每一行输出一行 JSON，数量、顺序、`id` 和 `source_hash` 完全一致。
2. 不输出 Markdown、代码围栏、开场白、总结或进度说明。
3. 不重复日文原句和官方翻译。
4. `words` 解释句子中的单词、固定表达和缩约形；常见助词放入 `grammar`，不要机械拆成词表。
5. `reading` 只写平假名；原词已经全是假名时写空字符串。
6. `pos`、`meaning`、`explanation`、`note` 使用简体中文并保持精炼。
7. `grammar` 只保留理解本句所需的关键结构。
8. 没有额外语气、典故或省略信息时，`note` 写空字符串。
9. 每个字段必须是单行字符串；需要并列时使用中文分号。
10. 你是个日语老师，整体解释要口语化，讲解清晰。

## 输出

每行严格使用以下结构，不增加或删除字段：

```json
{"id":"TX_MS_SHO_EX3_0600_0010:0","source_hash":"0123456789ABCDEF","words":[{"surface":"雇う","reading":"やとう","pos":"他动词・五段","meaning":"雇用；付报酬请人做事"}],"grammar":[{"pattern":"普通形＋だと？","explanation":"引用对方的话并反问，表示惊讶、怀疑或不满"}],"note":"わし是男性年长者使用的自称。"}
```

字段定义：

- `source_hash`：原样复制输入值，不自行计算或修改。
- `words[]`：`surface`、`reading`、`pos`、`meaning`。
- `grammar[]`：`pattern`、`explanation`。
- `note`：只放无法归入词汇或语法的语气、文化背景、指代和省略说明。

结果保存到输入清单指定的同名 `scripts\analysis/results/NNNN.jsonl`。完成后运行：

```powershell
python scripts\analysis\tools\dataset.py validate --dataset-dir scripts\analysis
```

全部批次完成时增加 `--require-complete`，校验所有结果文件是否齐全。校验只检查结构、条目数量、顺序和 ID；解析内容由 Agent 负责。

## 生成游戏数据

把当前已经完成且结构有效的批次合并为 Mod 可直接查询的运行时文本：

```powershell
python scripts\analysis\tools\dataset.py build-runtime --dataset-dir scripts\analysis --output mod\Scripts\analysis_ja.tsv
```

该命令按 `row_name + text_index` 建立索引。尚未生成的批次会被跳过，因此解析进行期间也可以重复生成；全部完成后增加 `--require-complete`。生成的 `mod/Scripts/analysis_ja.tsv` 受 `.gitignore` 排除，只进入玩家发布包。

## 查看器

`analysis_viewer.py` 启动只读本地网页，按 `(id, source_hash)` 对照 `scripts/analysis/input` 与 `scripts/analysis/results`，显示日文、官方简体中文、相邻上下文、词汇、语法和补充说明：

```powershell
python scripts\analysis\tools\analysis_viewer.py --batch 0001
```

不传 `--batch` 时默认打开 `0001`；网页中可以切换批次和搜索当前批次。查看器不修改输入或结果文件。
