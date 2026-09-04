# 台词离线解析工具

本目录负责在游戏外导出日语或英语台词、约束 Agent 输出、校验结果、浏览数据并合并查询表，不参与游戏运行时。

每种语言使用独立工作区，避免重新导出一种语言时覆盖另一种语言的数据：

```text
scripts/analysis/
├─ ja/
│  ├─ input/
│  ├─ results/
│  └─ manifest.json
├─ en/
│  ├─ input/
│  ├─ results/
│  └─ manifest.json
└─ tools/
```

`ja/` 与 `en/` 下的输入、结果和 manifest 都是 Git 忽略的线下工作数据。

## 生成输入

日语：

```powershell
python scripts\analysis\tools\dataset.py export `
  --language ja `
  --source mod\Scripts\official_ja.tsv `
  --zh-cn mod\Scripts\official_zh_cn.tsv `
  --output-dir scripts\analysis\ja
```

英语：

```powershell
python scripts\analysis\tools\dataset.py export `
  --language en `
  --source mod\Scripts\official_en.tsv `
  --zh-cn mod\Scripts\official_zh_cn.tsv `
  --output-dir scripts\analysis\en
```

默认每个批次包含 50 条台词。需要调整时增加 `--batch-size <数量>`。重新导出只重建目标语言的 `input/*.jsonl` 与 `manifest.json`，不会删除 `results/`；源文本变化后，新的 `source_hash` 会让旧结果在校验时失效。

## 输入格式

每个输入文件是 JSONL，每行是一条独立台词。日语记录使用 `ja`：

```json
{"id":"ROW_NAME:0","row_name":"ROW_NAME","text_index":0,"ja":"対象の日本語台詞","official_zh_cn":"官方简体中文台词","context_before":null,"context_after":{"ja":"下一条日语台词","official_zh_cn":"下一条官方简体中文台词"},"source_hash":"0123456789ABCDEF"}
```

英语记录使用 `en`：

```json
{"id":"ROW_NAME:0","row_name":"ROW_NAME","text_index":0,"en":"The target English line.","official_zh_cn":"官方简体中文台词","context_before":null,"context_after":{"en":"The next English line.","official_zh_cn":"下一条官方简体中文台词"},"source_hash":"0123456789ABCDEF"}
```

- `id` 和 `source_hash` 是结果必须原样返回的稳定键。
- `ja` 或 `en` 是唯一需要解析的目标文本。
- `official_zh_cn` 只用于消歧，不需要重新翻译或改写。
- `context_before`、`context_after` 只用于判断省略、指代和语气，不属于目标结果。

## Agent 通用指令

处理一个输入文件时使用以下约束：

1. 按输入顺序为每一行输出一行 JSON，数量、顺序、`id` 和 `source_hash` 完全一致。
2. 不输出 Markdown、代码围栏、开场白、总结或进度说明。
3. 不重复目标原句和官方翻译。
4. `words` 只保留理解本句有帮助的单词、固定表达、缩约形或习语，不机械拆分所有基础词。
5. `grammar` 只保留理解本句所需的关键结构。
6. `pos`、`meaning`、`explanation`、`note` 使用简体中文并保持精炼、口语化和清晰。
7. 没有额外语气、典故、指代或省略信息时，`note` 写空字符串。
8. 每个字段必须是单行字符串；需要并列时使用中文分号。
9. 每行只允许固定结构中的字段，不增加或删除字段。

## 日语结果格式

日语解析使用 `reading`，只写平假名；词面已经全是假名时写空字符串。常见助词归入 `grammar`，不单独机械列词。

```json
{"id":"ROW_NAME:0","source_hash":"0123456789ABCDEF","words":[{"surface":"雇う","reading":"やとう","pos":"他动词・五段","meaning":"雇用；付报酬请人做事"}],"grammar":[{"pattern":"普通形＋だと？","explanation":"引用对方的话并反问，表示惊讶、怀疑或不满"}],"note":"わし是男性年长者使用的自称。"}
```

## 英语结果格式

英语解析使用 `pronunciation`：写常见词典 IPA，不加两侧斜杠；没有可靠或有必要提示的读音时写空字符串。短语动词、习语和缩约形优先作为完整表达解释，语法项说明本句中的时态、语气、从句、倒装或省略等关键结构。

```json
{"id":"ROW_NAME:0","source_hash":"0123456789ABCDEF","words":[{"surface":"treasure","pronunciation":"ˈtreʒər","pos":"名词","meaning":"宝物；珍视的人或事物"}],"grammar":[{"pattern":"You mean ...?","explanation":"复述对方的意思并确认，常带惊讶或怀疑语气"}],"note":"这里的 treasure 指说话者最珍视的人，而不是财物。"}
```

结果保存到对应输入清单指定的同名文件：

```text
scripts/analysis/ja/results/NNNN.jsonl
scripts/analysis/en/results/NNNN.jsonl
```

## 校验结果

校验日语或英语的当前完成情况：

```powershell
python scripts\analysis\tools\dataset.py validate --dataset-dir scripts\analysis\ja
python scripts\analysis\tools\dataset.py validate --dataset-dir scripts\analysis\en
```

全部批次完成时增加 `--require-complete`。校验会按 manifest 中的语言检查对应字段，并核对条目数量、顺序、`id` 和 `source_hash`；解析内容本身由 Agent 负责。

## 合并查询表

把当前已经完成且结构有效的批次合并成按 `row_name + text_index` 查询的 UTF-8 TSV：

```powershell
python scripts\analysis\tools\dataset.py build-runtime `
  --dataset-dir scripts\analysis\ja `
  --output mod\Scripts\analysis_ja.tsv

python scripts\analysis\tools\dataset.py build-runtime `
  --dataset-dir scripts\analysis\en `
  --output mod\Scripts\analysis_en.tsv
```

尚未生成的批次会被跳过，因此解析进行期间也可以重复合并；要求全部批次完成时增加 `--require-complete`。生成的 TSV 受 `.gitignore` 排除。

## 查看器

查看器按 `(id, source_hash)` 对照指定语言的输入与结果，显示原文、官方简体中文、相邻上下文、词汇、语法和补充说明：

```powershell
python scripts\analysis\tools\analysis_viewer.py --language ja --batch 0001
python scripts\analysis\tools\analysis_viewer.py --language en --batch 0001
```

不传 `--language` 和 `--batch` 时默认打开日语 `0001`。也可以用 `--dataset-dir` 指向明确的数据集目录；查看器只读，不修改输入或结果文件。
