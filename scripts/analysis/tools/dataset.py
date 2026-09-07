import argparse
import hashlib
import json
from pathlib import Path


SCHEMA_VERSION = 2
RESULT_KEYS = {"id", "source_hash", "words", "grammar"}
GRAMMAR_KEYS = {"pattern", "explanation"}
LANGUAGE_SPECS = {
    "JA": {
        "input_field": "ja",
        "pronunciation_field": "reading",
        "runtime_header": "# OctopathDialogueAssistant analysis JA dialogue v1",
    },
    "EN": {
        "input_field": "en",
        "pronunciation_field": "pronunciation",
        "runtime_header": "# OctopathDialogueAssistant analysis EN dialogue v1",
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def unescape_field(value: str) -> str:
    result: list[str] = []
    index = 0
    escapes = {"\\": "\\", "t": "\t", "r": "\r", "n": "\n"}
    while index < len(value):
        current = value[index]
        if current == "\\" and index + 1 < len(value):
            escaped = value[index + 1]
            replacement = escapes.get(escaped)
            if replacement is not None:
                result.append(replacement)
                index += 2
                continue
        result.append(current)
        index += 1
    return "".join(result)


def load_dialogue_table(path: Path) -> tuple[list[tuple[str, int, str]], dict[tuple[str, int], str]]:
    ordered: list[tuple[str, int, str]] = []
    indexed: dict[tuple[str, int], str] = {}
    with path.open("r", encoding="utf-8") as source:
        header = source.readline().rstrip("\r\n")
        if not header.startswith("# OctopathDialogueAssistant official "):
            raise RuntimeError(f"Unsupported dialogue table: {path}")
        for line_number, line in enumerate(source, start=2):
            line = line.rstrip("\r\n")
            if not line:
                continue
            parts = line.split("\t", 2)
            if len(parts) != 3:
                raise RuntimeError(f"Malformed dialogue row at {path}:{line_number}")
            row_name, raw_index, raw_text = parts
            key = (row_name, int(raw_index))
            if key in indexed:
                raise RuntimeError(f"Duplicate dialogue key: {row_name}:{raw_index}")
            text = unescape_field(raw_text)
            ordered.append((row_name, key[1], text))
            indexed[key] = text
    return ordered, indexed


def source_hash(item: dict[str, object]) -> str:
    encoded = json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16].upper()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as output:
            for row in rows:
                output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()


def export_dataset(args: argparse.Namespace) -> None:
    language = args.language.upper()
    spec = LANGUAGE_SPECS[language]
    input_field = str(spec["input_field"])
    source_path = args.source.resolve()
    zh_path = args.zh_cn.resolve()
    output_dir = args.output_dir.resolve()
    input_dir = output_dir / "input"
    input_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "results").mkdir(parents=True, exist_ok=True)

    for previous in input_dir.glob("*.jsonl"):
        previous.unlink()

    ordered, _ = load_dialogue_table(source_path)
    _, translations = load_dialogue_table(zh_path)
    rows: list[dict[str, object]] = []
    for row_name, text_index, source_text in ordered:
        if not source_text.strip():
            continue
        item: dict[str, object] = {
            "id": f"{row_name}:{text_index}",
            "row_name": row_name,
            "text_index": text_index,
            input_field: source_text,
            "official_zh_cn": translations.get((row_name, text_index), ""),
        }
        item["source_hash"] = source_hash(item)
        rows.append(item)

    batches: list[dict[str, object]] = []
    for offset in range(0, len(rows), args.batch_size):
        batch_number = len(batches) + 1
        batch_id = f"{batch_number:04d}"
        file_name = f"{batch_id}.jsonl"
        batch_rows = rows[offset : offset + args.batch_size]
        write_jsonl(input_dir / file_name, batch_rows)
        batches.append(
            {
                "id": batch_id,
                "input": f"input/{file_name}",
                "result": f"results/{file_name}",
                "count": len(batch_rows),
            }
        )

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "language": language,
        "entry_count": len(rows),
        "batch_size": args.batch_size,
        "batch_count": len(batches),
        "source": {
            f"{input_field}_sha256": sha256(source_path),
            "zh_cn_sha256": sha256(zh_path),
        },
        "batches": batches,
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"analysis_entries={len(rows)}")
    print(f"analysis_batches={len(batches)}")
    print(f"analysis_output={output_dir}")


def require_single_line_string(value: object, field: str, source: Path, line_number: int) -> None:
    if not isinstance(value, str):
        raise RuntimeError(f"{source}:{line_number} field {field} must be a string")
    if "\r" in value or "\n" in value:
        raise RuntimeError(f"{source}:{line_number} field {field} must be a single line")


def validate_result_item(
    item: object, source: Path, line_number: int, language: str
) -> tuple[str, str]:
    if not isinstance(item, dict) or set(item) != RESULT_KEYS:
        raise RuntimeError(f"{source}:{line_number} result keys must be {sorted(RESULT_KEYS)}")
    require_single_line_string(item["id"], "id", source, line_number)
    require_single_line_string(item["source_hash"], "source_hash", source, line_number)
    if not isinstance(item["words"], list):
        raise RuntimeError(f"{source}:{line_number} words must be an array")
    if not isinstance(item["grammar"], list):
        raise RuntimeError(f"{source}:{line_number} grammar must be an array")
    pronunciation_field = str(LANGUAGE_SPECS[language]["pronunciation_field"])
    word_keys = {"surface", pronunciation_field, "pos", "meaning"}
    for word in item["words"]:
        if not isinstance(word, dict) or set(word) != word_keys:
            raise RuntimeError(
                f"{source}:{line_number} word keys must be {sorted(word_keys)}"
            )
        for key in word_keys:
            require_single_line_string(word[key], f"words.{key}", source, line_number)
    for grammar in item["grammar"]:
        if not isinstance(grammar, dict) or set(grammar) != GRAMMAR_KEYS:
            raise RuntimeError(f"{source}:{line_number} invalid grammar object")
        for key in GRAMMAR_KEYS:
            require_single_line_string(grammar[key], f"grammar.{key}", source, line_number)
    return item["id"], item["source_hash"]


def validate_input_item(
    item: object, source: Path, line_number: int, language: str
) -> tuple[str, str]:
    input_field = str(LANGUAGE_SPECS[language]["input_field"])
    expected_keys = {
        "id", "row_name", "text_index", input_field, "official_zh_cn", "source_hash"
    }
    if not isinstance(item, dict) or set(item) != expected_keys:
        raise RuntimeError(f"{source}:{line_number} input keys must be {sorted(expected_keys)}")
    for field in ("id", "row_name", "source_hash"):
        require_single_line_string(item[field], field, source, line_number)
    if not isinstance(item[input_field], str):
        raise RuntimeError(f"{source}:{line_number} field {input_field} must be a string")
    if not isinstance(item["official_zh_cn"], str):
        raise RuntimeError(f"{source}:{line_number} field official_zh_cn must be a string")
    if not isinstance(item["text_index"], int):
        raise RuntimeError(f"{source}:{line_number} field text_index must be an integer")
    return item["id"], item["source_hash"]


def read_identities(path: Path, result: bool, language: str) -> list[tuple[str, str]]:
    identities: list[tuple[str, str]] = []
    with path.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            if not line.strip():
                continue
            item = json.loads(line)
            if result:
                identities.append(validate_result_item(item, path, line_number, language))
            else:
                identities.append(validate_input_item(item, path, line_number, language))
    return identities


def read_manifest(dataset_dir: Path) -> tuple[dict[str, object], str]:
    manifest = json.loads((dataset_dir / "manifest.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise RuntimeError("Dataset manifest must be a JSON object")
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise RuntimeError(
            f"Unsupported dataset schema: {manifest.get('schema_version')}; expected {SCHEMA_VERSION}"
        )
    language = manifest.get("language")
    if language not in LANGUAGE_SPECS:
        raise RuntimeError(f"Unsupported or missing dataset language: {language}")
    return manifest, str(language)


def validate_results(args: argparse.Namespace) -> None:
    dataset_dir = args.dataset_dir.resolve()
    manifest, language = read_manifest(dataset_dir)
    validated = 0
    missing = 0
    for batch in manifest["batches"]:
        input_path = dataset_dir / batch["input"]
        result_path = dataset_dir / batch["result"]
        if not result_path.exists():
            missing += 1
            continue
        input_identities = read_identities(input_path, result=False, language=language)
        result_identities = read_identities(result_path, result=True, language=language)
        if input_identities != result_identities:
            raise RuntimeError(f"Result ids, source hashes, or order do not match: {result_path}")
        validated += 1
    if args.require_complete and missing:
        raise RuntimeError(f"Missing result batches: {missing}")
    print(f"validated_batches={validated}")
    print(f"missing_batches={missing}")


def read_jsonl(path: Path) -> list[object]:
    rows: list[object] = []
    with path.open("r", encoding="utf-8") as source:
        for line in source:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def format_analysis(item: dict[str, object], language: str) -> str:
    lines: list[str] = []
    words = item["words"]
    if isinstance(words, list) and words:
        lines.append("【词汇】")
        for raw_word in words:
            word = raw_word if isinstance(raw_word, dict) else {}
            surface = str(word.get("surface", ""))
            pronunciation_field = str(LANGUAGE_SPECS[language]["pronunciation_field"])
            pronunciation = str(word.get(pronunciation_field, ""))
            part_of_speech = str(word.get("pos", ""))
            meaning = str(word.get("meaning", ""))
            label = surface
            if pronunciation:
                if language == "EN":
                    label += f" /{pronunciation.strip().strip('/')}/"
                else:
                    label += f"（{pronunciation}）"
            if part_of_speech:
                label += f"〔{part_of_speech}〕"
            lines.append(f"{label}：{meaning}" if meaning else label)

    grammar = item["grammar"]
    if isinstance(grammar, list) and grammar:
        lines.append("【语法】")
        for raw_grammar in grammar:
            entry = raw_grammar if isinstance(raw_grammar, dict) else {}
            pattern = str(entry.get("pattern", ""))
            explanation = str(entry.get("explanation", ""))
            lines.append(f"{pattern}：{explanation}" if explanation else pattern)

    return "\n".join(lines) if lines else "当前台词没有需要说明的词汇或语法。"


def escape_runtime_field(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")


def build_runtime_analysis(args: argparse.Namespace) -> None:
    dataset_dir = args.dataset_dir.resolve()
    output = args.output.resolve()
    manifest, language = read_manifest(dataset_dir)
    runtime_rows: list[tuple[str, int, str]] = []
    seen: set[tuple[str, int]] = set()
    used_batches = 0
    missing_batches = 0
    invalid_batches = 0

    for batch in manifest["batches"]:
        input_path = dataset_dir / batch["input"]
        result_path = dataset_dir / batch["result"]
        if not result_path.exists():
            missing_batches += 1
            continue
        try:
            inputs = read_jsonl(input_path)
            results = read_jsonl(result_path)
            input_identities = read_identities(input_path, result=False, language=language)
            result_identities = read_identities(result_path, result=True, language=language)
            if input_identities != result_identities or len(inputs) != len(results):
                raise RuntimeError("result identities do not match input")
            batch_rows: list[tuple[str, int, str]] = []
            for source, result in zip(inputs, results):
                if not isinstance(source, dict) or not isinstance(result, dict):
                    raise RuntimeError("input or result row is not an object")
                row_name = source.get("row_name")
                text_index = source.get("text_index")
                if not isinstance(row_name, str) or not isinstance(text_index, int):
                    raise RuntimeError("input dialogue identity is missing")
                key = (row_name, text_index)
                if key in seen:
                    raise RuntimeError(f"duplicate dialogue identity: {row_name}:{text_index}")
                batch_rows.append((row_name, text_index, format_analysis(result, language)))
            for row_name, text_index, text in batch_rows:
                seen.add((row_name, text_index))
                runtime_rows.append((row_name, text_index, text))
            used_batches += 1
        except (OSError, ValueError, TypeError, KeyError, RuntimeError, json.JSONDecodeError):
            invalid_batches += 1

    if args.require_complete and (missing_batches or invalid_batches):
        raise RuntimeError(
            f"Runtime analysis is incomplete: missing={missing_batches}, invalid={invalid_batches}"
        )
    if not runtime_rows:
        raise RuntimeError("No valid analysis results are available")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as target:
            target.write(str(LANGUAGE_SPECS[language]["runtime_header"]) + "\n")
            for row_name, text_index, text in runtime_rows:
                target.write(f"{row_name}\t{text_index}\t{escape_runtime_field(text)}\n")
        temporary.replace(output)
    finally:
        if temporary.exists():
            temporary.unlink()

    print(f"analysis_runtime_entries={len(runtime_rows)}")
    print(f"analysis_runtime_batches={used_batches}")
    print(f"analysis_missing_batches={missing_batches}")
    print(f"analysis_invalid_batches={invalid_batches}")
    print(f"analysis_runtime_output={output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("--language", required=True, choices=("ja", "en"))
    export_parser.add_argument("--source", required=True, type=Path)
    export_parser.add_argument("--zh-cn", required=True, type=Path)
    export_parser.add_argument("--output-dir", required=True, type=Path)
    export_parser.add_argument("--batch-size", type=int, default=50)
    export_parser.set_defaults(handler=export_dataset)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--dataset-dir", required=True, type=Path)
    validate_parser.add_argument("--require-complete", action="store_true")
    validate_parser.set_defaults(handler=validate_results)

    runtime_parser = subparsers.add_parser("build-runtime")
    runtime_parser.add_argument("--dataset-dir", required=True, type=Path)
    runtime_parser.add_argument("--output", required=True, type=Path)
    runtime_parser.add_argument("--require-complete", action="store_true")
    runtime_parser.set_defaults(handler=build_runtime_analysis)

    args = parser.parse_args()
    if args.command == "export" and args.batch_size < 1:
        parser.error("--batch-size must be positive")
    return args


def main() -> None:
    args = parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
