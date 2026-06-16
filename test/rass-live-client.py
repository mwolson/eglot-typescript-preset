#!/usr/bin/env python3

import argparse
import json
import queue
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import unquote


def send(proc, message):
    data = json.dumps(message).encode("utf-8")
    proc.stdin.write(f"Content-Length: {len(data)}\r\n\r\n".encode("ascii") + data)
    proc.stdin.flush()


def read_message(proc):
    content_length = None
    while True:
        line = proc.stdout.readline()
        if not line:
            return None
        if line == b"\r\n":
            break
        if line.lower().startswith(b"content-length:"):
            content_length = int(line.split(b":", 1)[1].strip())

    if content_length is None:
        raise RuntimeError("Missing Content-Length header")

    payload = proc.stdout.read(content_length)
    if not payload:
        return None
    return json.loads(payload.decode("utf-8"))


def start_message_reader(proc):
    message_queue = queue.Queue()

    def read_loop():
        try:
            while True:
                message = read_message(proc)
                message_queue.put(message)
                if message is None:
                    return
        except Exception as exc:
            message_queue.put(exc)

    thread = threading.Thread(target=read_loop, daemon=True)
    thread.start()
    return message_queue, thread


def wait_for_message(message_queue, timeout):
    try:
        message = message_queue.get(timeout=timeout)
    except queue.Empty:
        return None
    if isinstance(message, Exception):
        raise message
    return message


def request(proc, next_id, method, params):
    send(proc, {"jsonrpc": "2.0", "id": next_id, "method": method, "params": params})
    return next_id + 1


def path_to_raw_uri(p):
    """Convert path to file URI without percent-encoding (like Eglot)."""
    return "file://" + str(p)


def parse_file_arg(arg):
    """Parse 'path:language-id' into (resolved_path, language_id)."""
    if ":" not in arg:
        raise ValueError(f"File argument must be 'path:language-id', got: {arg}")
    path_str, lang_id = arg.rsplit(":", 1)
    return Path(path_str).resolve(), lang_id


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("preset")
    parser.add_argument("files", nargs="+", help="file:language-id pairs")
    parser.add_argument("--server", default="rass")
    parser.add_argument("--root", default=None)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument(
        "--settle",
        type=float,
        default=1.5,
        help="seconds with no diagnostic events before exiting",
    )
    parser.add_argument(
        "--min-events",
        type=int,
        default=1,
        dest="min_events",
        help="minimum publishDiagnostics events per file before settle starts",
    )
    parser.add_argument("--stderr", action="store_true")
    parser.add_argument(
        "--raw-uri",
        action="store_true",
        dest="raw_uri",
        help="send file URIs without percent-encoding (like Eglot)",
    )
    args = parser.parse_args()

    files = [parse_file_arg(f) for f in args.files]
    root_path = Path(args.root).resolve() if args.root else files[0][0].parent
    to_uri = path_to_raw_uri if args.raw_uri else Path.as_uri

    proc = subprocess.Popen(
        [args.server, args.preset],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    next_id = 1
    workspace_sections = []
    per_file = {}
    files_with_diags = set()
    diag_event_count = {}
    all_file_uris = set()
    for file_path, _ in files:
        uri = to_uri(file_path)
        per_file[uri] = {"diagnosticSources": [], "diagnosticCodes": []}
        diag_event_count[uri] = 0
        all_file_uris.add(uri)
    initialized = False
    message_queue, reader_thread = start_message_reader(proc)

    try:
        next_id = request(
            proc,
            next_id,
            "initialize",
            {
                "processId": None,
                "rootUri": to_uri(root_path),
                "capabilities": {
                    "workspace": {"configuration": True},
                    "textDocument": {
                        "publishDiagnostics": {},
                        "$streamingDiagnostics": True,
                    },
                },
                "workspaceFolders": [
                    {
                        "uri": to_uri(root_path),
                        "name": root_path.name or "workspace",
                    }
                ],
            },
        )

        deadline = time.monotonic() + args.timeout
        files_opened = False
        stable_since = None

        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break

            if initialized and files_opened:
                poll_interval = 0.1
            else:
                poll_interval = max(0.0, deadline - time.monotonic())
            message = wait_for_message(
                message_queue,
                min(poll_interval, max(0.0, deadline - time.monotonic())),
            )
            if message is None:
                if (
                    initialized
                    and files_opened
                    and files_with_diags >= all_file_uris
                    and stable_since is not None
                ):
                    idle = time.monotonic() - stable_since
                    events_met = all(
                        diag_event_count[u] >= args.min_events
                        for u in all_file_uris
                    )
                    if events_met and idle > args.settle:
                        break
                    if idle > args.settle * 2:
                        break
                continue

            method = message.get("method")

            if "id" in message and message.get("id") == 1 and "result" in message:
                initialized = True
                send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})
                for file_path, lang_id in files:
                    content = file_path.read_text(encoding="utf-8")
                    send(
                        proc,
                        {
                            "jsonrpc": "2.0",
                            "method": "textDocument/didOpen",
                            "params": {
                                "textDocument": {
                                    "uri": to_uri(file_path),
                                    "languageId": lang_id,
                                    "version": 1,
                                    "text": content,
                                }
                            },
                        },
                    )
                files_opened = True
                continue

            if method == "workspace/configuration":
                for item in message.get("params", {}).get("items", []):
                    workspace_sections.append(item.get("section", ""))
                send(
                    proc,
                    {
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "result": [
                            None for _ in message.get("params", {}).get("items", [])
                        ],
                    },
                )
                continue

            if method == "client/registerCapability":
                send(
                    proc,
                    {
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "result": None,
                    },
                )
                continue

            if method in (
                "textDocument/publishDiagnostics",
                "$/streamDiagnostics",
            ):
                diag_uri = message.get("params", {}).get("uri", "")
                if args.raw_uri:
                    diag_uri = unquote(diag_uri)
                entry = per_file.get(diag_uri)
                if entry is not None:
                    files_with_diags.add(diag_uri)
                    diag_event_count[diag_uri] += 1
                    for diagnostic in message.get("params", {}).get(
                        "diagnostics", []
                    ):
                        source = diagnostic.get("source")
                        code = diagnostic.get("code")
                        if source is not None:
                            entry["diagnosticSources"].append(str(source))
                        if code is not None:
                            entry["diagnosticCodes"].append(str(code))
                    stable_since = time.monotonic()
                continue

        try:
            next_id = request(proc, next_id, "shutdown", None)
            end_deadline = time.monotonic() + 2.0
            while time.monotonic() < end_deadline:
                message = wait_for_message(
                    message_queue, max(0.0, end_deadline - time.monotonic())
                )
                if message is None:
                    continue
                if message.get("id") == next_id - 1:
                    break
            send(proc, {"jsonrpc": "2.0", "method": "exit", "params": {}})
        except BrokenPipeError:
            pass
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
        try:
            proc.wait(timeout=1.0)
        except Exception:
            proc.kill()
        reader_thread.join(timeout=1.0)

    result = {
        "initialized": initialized,
        "workspaceConfigSections": workspace_sections,
        "files": {uri: data for uri, data in per_file.items()},
    }

    if args.stderr:
        try:
            stderr_output = proc.stderr.read().decode("utf-8", errors="replace")
            # Truncated to keep harness output readable. rass event logs can
            # run long; if you need the full stream, spawn rass directly from
            # a debug script that drains stderr in a thread (see AGENTS.md
            # "Debugging live tests").
            result["stderr"] = stderr_output[:4000] if stderr_output else ""
        except Exception:
            result["stderr"] = ""

    print(json.dumps(result))


if __name__ == "__main__":
    main()
