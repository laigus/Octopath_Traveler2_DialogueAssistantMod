import argparse
import json
from pathlib import Path


LANGUAGES = ("JA", "EN", "IT", "FR", "DE", "ES", "ZH_TW", "ZH_CN", "KR")


def escape_field(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--language", required=True, choices=LANGUAGES)
    args = parser.parse_args()

    with args.input.open("r", encoding="utf-8-sig") as source:
        asset = json.load(source)

    exports = asset.get("Exports", [])
    if not exports or exports[0].get("$type", "").split(",", 1)[0] != "UAssetAPI.ExportTypes.DataTableExport":
        raise RuntimeError(f"TalkData_{args.language} is not a DataTable export")

    rows = exports[0]["Table"]["Data"]
    lines = [f"# OctopathDialogueAssistant official {args.language} dialogue v1"]
    written_rows = 0
    written_texts = 0
    for row in rows:
        row_name = row.get("Name", "")
        if not row_name:
            continue
        text_property = next((item for item in row.get("Value", []) if item.get("Name") == "Text"), None)
        if text_property is None:
            continue
        text_values = text_property.get("Value", [])
        for index, item in enumerate(text_values):
            text = item.get("Value", "")
            if text is None:
                text = ""
            if not isinstance(text, str):
                raise RuntimeError(f"Unexpected Text value in {row_name}[{index}]")
            lines.append(f"{row_name}\t{index}\t{escape_field(text)}")
            written_texts += 1
        written_rows += 1

    if written_rows < 30000 or written_texts < written_rows:
        raise RuntimeError(
            f"Official dialogue export is incomplete: rows={written_rows}, texts={written_texts}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"translation_rows={written_rows}")
    print(f"translation_texts={written_texts}")
    print(f"translation_language={args.language}")
    print(f"translation_output={args.output}")


if __name__ == "__main__":
    main()
