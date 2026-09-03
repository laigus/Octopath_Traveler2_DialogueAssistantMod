"""本地台词解析查看器。

启动后提供一个只读的本地网页界面，按批次读取 analysis/input 与 analysis/results，
避免直接打开 JSONL 时难以对照原文和解析。

启动示例：
    python scripts\\analysis\\tools\\analysis_viewer.py --batch 0001
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional
from urllib.parse import unquote, urlparse


APP_TITLE = "台词解析查看器"
BATCH_NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    """以 UTF-8 读取 JSONL，并保留输入顺序。"""

    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if not raw_line.strip():
                continue
            try:
                value = json.loads(raw_line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path.name} 第 {line_number} 行 JSON 无效：{exc.msg}") from exc
            if not isinstance(value, dict):
                raise ValueError(f"{path.name} 第 {line_number} 行不是 JSON 对象")
            records.append(value)
    return records


def text_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.replace("\\r\\n", "\\n")
    return str(value)


def record_key(record: dict[str, Any]) -> tuple[str, str]:
    return text_value(record.get("id")), text_value(record.get("source_hash"))


def context_payload(context: Any) -> Optional[dict[str, str]]:
    if not isinstance(context, dict):
        return None
    return {
        "ja": text_value(context.get("ja")),
        "official_zh_cn": text_value(context.get("official_zh_cn")),
    }


def build_batch_payload(dataset_dir: Path, batch: str) -> dict[str, Any]:
    """读取一个批次并把输入与结果按稳定键关联。"""

    if not BATCH_NAME_RE.fullmatch(batch):
        raise ValueError("批次名称包含不允许的字符")

    input_path = dataset_dir / "input" / f"{batch}.jsonl"
    result_path = dataset_dir / "results" / f"{batch}.jsonl"
    if not input_path.is_file():
        raise FileNotFoundError(f"找不到输入批次：{batch}.jsonl")

    inputs = read_jsonl(input_path)
    results: list[dict[str, Any]] = []
    result_error = ""
    if result_path.is_file():
        try:
            results = read_jsonl(result_path)
        except (OSError, ValueError) as exc:
            result_error = str(exc)

    result_map: dict[tuple[str, str], dict[str, Any]] = {}
    duplicate_keys: set[tuple[str, str]] = set()
    for result in results:
        key = record_key(result)
        if key in result_map:
            duplicate_keys.add(key)
        result_map[key] = result

    payload_records: list[dict[str, Any]] = []
    input_keys: set[tuple[str, str]] = set()
    for input_record in inputs:
        key = record_key(input_record)
        input_keys.add(key)
        analysis = result_map.get(key)
        issue = ""
        if result_error:
            issue = result_error
        elif not result_path.is_file():
            issue = "尚未生成对应的解析结果"
        elif analysis is None:
            issue = "结果文件中没有匹配的 id/source_hash"
        elif key in duplicate_keys:
            issue = "结果文件存在重复的 id/source_hash"
        payload_records.append(
            {
                "id": text_value(input_record.get("id")),
                "source_hash": text_value(input_record.get("source_hash")),
                "row_name": text_value(input_record.get("row_name")),
                "text_index": input_record.get("text_index"),
                "ja": text_value(input_record.get("ja")),
                "official_zh_cn": text_value(input_record.get("official_zh_cn")),
                "context_before": context_payload(input_record.get("context_before")),
                "context_after": context_payload(input_record.get("context_after")),
                "analysis": analysis,
                "issue": issue,
            }
        )

    return {
        "batch": batch,
        "record_count": len(payload_records),
        "parsed_count": sum(1 for item in payload_records if item["analysis"] is not None and not item["issue"]),
        "stale_result_count": sum(1 for key in result_map if key not in input_keys),
        "result_exists": result_path.is_file(),
        "result_error": result_error,
        "records": payload_records,
    }


class ViewerHandler(BaseHTTPRequestHandler):
    dataset_dir: Path
    html_path: Path

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API name
        parsed = urlparse(self.path)
        route = unquote(parsed.path)
        try:
            if route == "/" or route == "/analysis_viewer.html":
                self._send_bytes(self.html_path.read_bytes(), "text/html; charset=utf-8")
                return
            if route == "/api/batches":
                self._send_json(self._list_batches())
                return
            if route.startswith("/api/batch/"):
                batch = route.removeprefix("/api/batch/")
                self._send_json(build_batch_payload(self.dataset_dir, batch))
                return
            self._send_error_json(404, "找不到请求资源")
        except FileNotFoundError as exc:
            self._send_error_json(404, str(exc))
        except (OSError, ValueError) as exc:
            self._send_error_json(400, str(exc))

    def _list_batches(self) -> dict[str, Any]:
        input_dir = self.dataset_dir / "input"
        names = sorted(path.stem for path in input_dir.glob("*.jsonl")) if input_dir.is_dir() else []
        return {
            "batches": [
                {
                    "name": name,
                    "result_exists": (self.dataset_dir / "results" / f"{name}.jsonl").is_file(),
                }
                for name in names
            ]
        }

    def _send_json(self, value: Any, status: int = 200) -> None:
        body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, status: int, message: str) -> None:
        self._send_json({"error": message}, status=status)

    def _send_bytes(self, body: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *_args: Any) -> None:
        return


def make_handler(dataset_dir: Path, html_path: Path) -> type[ViewerHandler]:
    class BoundViewerHandler(ViewerHandler):
        pass

    BoundViewerHandler.dataset_dir = dataset_dir.resolve()
    BoundViewerHandler.html_path = html_path.resolve()
    return BoundViewerHandler


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="启动本地台词解析查看器")
    parser.add_argument("--batch", default="0001", help="启动时打开的批次，默认 0001")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址，默认仅本机访问")
    parser.add_argument("--port", type=int, default=0, help="监听端口，0 表示自动选择空闲端口")
    parser.add_argument("--no-browser", action="store_true", help="只启动服务，不自动打开浏览器")
    parser.add_argument(
        "--dataset-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="解析数据目录，默认根据脚本位置使用 scripts/analysis",
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    dataset_dir = args.dataset_dir.resolve()
    html_path = Path(__file__).resolve().with_name("analysis_viewer.html")
    if not html_path.is_file():
        print(f"找不到界面文件：{html_path}", file=sys.stderr)
        return 1

    handler = make_handler(dataset_dir, html_path)
    try:
        server = ThreadingHTTPServer((args.host, args.port), handler)
    except OSError as exc:
        print(f"本地服务启动失败：{exc}", file=sys.stderr)
        return 1

    host, port = server.server_address[:2]
    url = f"http://{host}:{port}/?batch={args.batch}"
    print(f"{APP_TITLE}：{url}", flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
