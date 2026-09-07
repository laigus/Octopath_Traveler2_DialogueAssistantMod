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
{"id":"ROW_NAME:0","row_name":"ROW_NAME","text_index":0,"ja":"対象の日本語台詞","official_zh_cn":"官方简体中文台词","source_hash":"0123456789ABCDEF"}
```

英语记录使用 `en`：

```json
{"id":"ROW_NAME:0","row_name":"ROW_NAME","text_index":0,"en":"The target English line.","official_zh_cn":"官方简体中文台词","source_hash":"0123456789ABCDEF"}
```

- `id` 和 `source_hash` 是结果必须原样返回的稳定键。
- `ja` 或 `en` 是解析原文。
- `official_zh_cn` 是同句游戏官方简体中文，用于确认词义。
- 解析范围是当前句的词汇和语法。
- 纯标点台词的 `words`、`grammar` 必须为空数组。提交前逐条对照当前原句，不能只核对 ID 和哈希。

## Agent 通用指令

处理一个输入文件时使用以下约束：

1. 按输入顺序为每一行输出一行 JSON，数量、顺序、`id` 和 `source_hash` 完全一致。
2. 不输出 Markdown、代码围栏、开场白、总结或进度说明。
3. 不在结果中重复目标原句和官方翻译。
4. 解析当前记录的 `ja` 或 `en`，输出当前句的词汇和语法信息。
5. `words` 列出该句的单词，说明词性和含义。包含汉字的单词必须要列出。
6. `grammar` 列出句中的语法点，并说明结构、含义和用法。
7. 同一语言点只解释一次。词汇化的固定表达、缩约形和习语归入 `words`；可套用的句型、活用、助词组合和语法结构归入 `grammar`。边界模糊时选择更适合的一类。
8. `pos`、`meaning`、`explanation` 使用简体中文并保持精炼、口语化和清晰。
9. 每个字段必须是单行字符串；需要并列时使用中文分号。
10. 每行只允许固定结构中的字段，不增加或删除字段。

## 日语结果格式

日语 `words` 列出该句的单词，每个条目对应“词语（汉字假名注音）—词性，含义”。词面含有汉字时， `reading`写平假名读音；词面已经全是假名时，`reading` 写空字符串。助词作为句法结构发挥作用时归入 `grammar`。

日语 `grammar` 列出句中的语法点，每条说明结构、含义和用法。已在 `words` 中作为固定表达完整解释的内容不再写入 `grammar`。

```json
{"id":"ROW_NAME:0","source_hash":"0123456789ABCDEF","words":[{"surface":"雇う","reading":"やとう","pos":"他动词・五段","meaning":"雇用；付报酬请人做事"}],"grammar":[{"pattern":"普通形＋だと？","explanation":"引用对方的话并反问，表示惊讶、怀疑或不满"}]}
```

## 英语结果格式

英语解析使用 `pronunciation`：写常见词典 IPA，不加两侧斜杠；没有可靠读音时写空字符串。短语动词、习语和缩约形作为完整表达解释；语法项分别说明本句中的时态、语气、从句、倒装或省略等结构，且不重复 `words` 已解释的内容。

```json
{"id":"ROW_NAME:0","source_hash":"0123456789ABCDEF","words":[{"surface":"treasure","pronunciation":"ˈtreʒər","pos":"名词","meaning":"宝物；珍视的人或事物"}],"grammar":[{"pattern":"You mean ...?","explanation":"复述对方的意思并确认，常带惊讶或怀疑语气"}]}
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

查看器按 `(id, source_hash)` 对照指定语言的输入与结果，显示当前原文、同句官方简体中文、词汇和语法：

```powershell
python scripts\analysis\tools\analysis_viewer.py --language ja --batch 0001
python scripts\analysis\tools\analysis_viewer.py --language en --batch 0001
```

不传 `--language` 和 `--batch` 时默认打开日语 `0001`。也可以用 `--dataset-dir` 指向明确的数据集目录；查看器只读，不修改输入或结果文件。
