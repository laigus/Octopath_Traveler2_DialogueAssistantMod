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


def load_data_table(path: Path, description: str) -> list[dict[str, object]]:
    with path.open("r", encoding="utf-8-sig") as source:
        asset = json.load(source)
    exports = asset.get("Exports", [])
    if not exports or exports[0].get("$type", "").split(",", 1)[0] != "UAssetAPI.ExportTypes.DataTableExport":
        raise RuntimeError(f"{description} is not a DataTable export")
    return exports[0]["Table"]["Data"]


def dialogue_lines(rows: list[dict[str, object]]) -> tuple[list[str], int, int]:
    lines: list[str] = []
    written_rows = 0
    written_texts = 0
    for row in rows:
        row_name = row.get("Name", "")
        if not isinstance(row_name, str) or not row_name:
            continue
        values = row.get("Value", [])
        text_property = next(
            (item for item in values if isinstance(item, dict) and item.get("Name") == "Text"),
            None,
        )
        if text_property is None:
            continue
        text_values = text_property.get("Value", [])
        if not isinstance(text_values, list):
            raise RuntimeError(f"Unexpected Text array in {row_name}")
        for index, item in enumerate(text_values):
            text = item.get("Value", "") if isinstance(item, dict) else ""
            if text is None:
                text = ""
            if not isinstance(text, str):
                raise RuntimeError(f"Unexpected Text value in {row_name}[{index}]")
            lines.append(f"{row_name}\t{index}\t{escape_field(text)}")
            written_texts += 1
        written_rows += 1
    return lines, written_rows, written_texts


def field_info_ids(rows: list[dict[str, object]]) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()
    for row in rows:
        values = row.get("Value", [])
        history = next(
            (item for item in values if isinstance(item, dict) and item.get("Name") == "HistoryTextID"),
            None,
        )
        history_id = history.get("Value", "") if history is not None else ""
        if isinstance(history_id, str) and history_id and history_id != "None" and history_id not in seen:
            seen.add(history_id)
            ordered.append(history_id)
    return ordered


def game_text_map(rows: list[dict[str, object]]) -> dict[str, str]:
    texts: dict[str, str] = {}
    for row in rows:
        row_name = row.get("Name", "")
        if not isinstance(row_name, str) or not row_name:
            continue
        values = row.get("Value", [])
        text_property = next(
            (item for item in values if isinstance(item, dict) and item.get("Name") == "Text"),
            None,
        )
        if text_property is None:
            continue
        text = text_property.get("CultureInvariantString", "")
        if text is None:
            text = ""
        if not isinstance(text, str):
            raise RuntimeError(f"Unexpected GameText value in {row_name}")
        if text:
            texts[row_name] = text
    return texts


def write_table(path: Path, header: str, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join([header, *lines]) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--talk-input", required=True, type=Path)
    parser.add_argument("--game-text-input", required=True, type=Path)
    parser.add_argument("--npc-hear-input", required=True, type=Path)
    parser.add_argument("--dialogue-output", required=True, type=Path)
    parser.add_argument("--field-output", required=True, type=Path)
    parser.add_argument("--language", required=True, choices=LANGUAGES)
    args = parser.parse_args()

    talk_rows = load_data_table(args.talk_input, f"TalkData_{args.language}")
    game_text_rows = load_data_table(args.game_text_input, f"GameText{args.language}")
    npc_hear_rows = load_data_table(args.npc_hear_input, "NPCHearData")

    talk_lines, dialogue_rows, dialogue_texts = dialogue_lines(talk_rows)
    if dialogue_rows < 30000 or dialogue_texts < dialogue_rows:
        raise RuntimeError(
            f"Official dialogue export is incomplete: rows={dialogue_rows}, texts={dialogue_texts}"
        )

    game_texts = game_text_map(game_text_rows)
    history_ids = field_info_ids(npc_hear_rows)
    field_lines = [
        f"{history_id}\t0\t{escape_field(game_texts[history_id])}"
        for history_id in history_ids
        if history_id in game_texts
    ]
    if len(field_lines) < 500:
        raise RuntimeError(f"Official field-info export is incomplete: rows={len(field_lines)}")

    write_table(
        args.dialogue_output,
        f"# OctopathDialogueAssistant official {args.language} dialogue v1",
        talk_lines,
    )
    write_table(
        args.field_output,
        f"# OctopathDialogueAssistant official {args.language} field-info v1",
        field_lines,
    )
    print(f"translation_dialogue_rows={dialogue_rows}")
    print(f"translation_dialogue_texts={dialogue_texts}")
    print(f"translation_field_rows={len(field_lines)}")
    print(f"translation_language={args.language}")
    print(f"translation_dialogue_output={args.dialogue_output}")
    print(f"translation_field_output={args.field_output}")


if __name__ == "__main__":
    main()
