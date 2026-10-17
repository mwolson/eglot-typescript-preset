#!/usr/bin/env python3

import asyncio
import importlib.util
import json
import os
import re
import sys
import types
from pathlib import Path


def ensure_rassumfrassum_stubs():
    package = types.ModuleType("rassumfrassum")
    frassum = types.ModuleType("rassumfrassum.frassum")
    json_mod = types.ModuleType("rassumfrassum.json")
    util = types.ModuleType("rassumfrassum.util")

    class LspLogic:
        primary = None

        async def on_client_request(self, method, params, servers):
            return servers

        def process_request(self, method, params, server):
            # Mirrors rass 0.3.4+ handling of the "rass" key.
            init_opts = params.get("initializationOptions")
            if method == "initialize" and init_opts and "rass" in init_opts:
                generic = {k: v for k, v in init_opts.items() if k != "rass"}
                new_opts = generic
                for pattern, overlay in init_opts["rass"].items():
                    if re.search(pattern, server.name):
                        new_opts = dmerge(overlay, generic)
                        break
                params = {**params, "initializationOptions": new_opts}
            return params

        async def on_server_request(self, method, params, source):
            return None

    class DirectResponse:
        def __init__(self, payload=None, is_error=False):
            self.payload = payload
            self.is_error = is_error

    class Server:
        pass

    def dmerge(base, override):
        result = dict(base)
        for key, value in override.items():
            if isinstance(result.get(key), dict) and isinstance(value, dict):
                result[key] = dmerge(result[key], value)
            else:
                result[key] = value
        return result

    frassum.DirectResponse = DirectResponse
    def _diff_changes(old, new):
        raise AssertionError("preset should replace rass _diff_changes")

    frassum._diff_changes = _diff_changes
    frassum.LspLogic = LspLogic
    frassum.Server = Server
    json_mod.JSON = dict
    util.dmerge = dmerge

    sys.modules.setdefault("rassumfrassum", package)
    sys.modules["rassumfrassum.frassum"] = frassum
    sys.modules["rassumfrassum.json"] = json_mod
    sys.modules["rassumfrassum.util"] = util


DIFF_CASES = [
    ("one\x0c\ntwo\nthree\n", "one\x0c\ntwo\nTHREE\n"),
    ("one\rtwo\nthree\n", "one\rtwo\nTHREE\n"),
    ("one\u2028two\nthree\n", "one\u2028two\nTHREE\n"),
    ("one\x85two\nthree\n", "one\x85two\nTHREE\n"),
    ("a\r\nb\r\n", "a\r\nB\r\n"),
    ("// \U0001F600 x\n", "// \U0001F600! x\n"),
    ("aa", "aaa"),
    ("abc", ""),
    ("", "abc"),
    ("same\n", "same\n"),
]


def apply_changes(text, changes):
    """Apply LSP contentChanges using newline-only lines and UTF-16 columns."""

    def offset(pos):
        lines = text.split("\n")
        index = sum(len(line) + 1 for line in lines[: pos["line"]])
        units = 0
        for char in lines[pos["line"]] if pos["line"] < len(lines) else "":
            if units >= pos["character"]:
                break
            units += 2 if ord(char) > 0xFFFF else 1
            index += 1
        return index

    for change in changes:
        start = offset(change["range"]["start"])
        end = offset(change["range"]["end"])
        text = text[:start] + change["text"] + text[end:]
    return text


def diff_changes_failures(module):
    """Return the DIFF_CASES that _diff_changes does not reproduce."""
    return [
        [old, new]
        for old, new in DIFF_CASES
        if apply_changes(old, module._diff_changes(old, new)) != new
    ]


def load_module(path_str):
    ensure_rassumfrassum_stubs()
    path = Path(path_str)
    spec = importlib.util.spec_from_file_location("generated_rass_preset", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load preset module from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


async def diagnostic_pull_request(module):
    logic_cls = module.logic_class()
    server = sys.modules["rassumfrassum.frassum"].Server()
    server.name = "tsgo"
    server.caps = {"diagnosticProvider": {"interFileDependencies": False}}
    state = types.SimpleNamespace(docver=1, inflight_pulls={})
    requests = []
    notifications = []

    async def request_server(_server, method, params):
        requests.append({"method": method, "params": dict(params)})
        return False, {
            "kind": "full",
            "items": [{"code": 2322, "message": "Type mismatch"}],
        }

    async def notify_client(method, params):
        notifications.append({"method": method, "params": dict(params)})

    logic = logic_cls.__new__(logic_cls)
    logic.servers = {id(server): server}
    logic.request_server = request_server
    logic.notify_client = notify_client
    logic.documents = {}
    logic._stash_diagnostics_data = lambda _diags, _server, _state: None

    await logic._pull_and_stream_diags("file:///x.ts", state, False)
    for _ in range(10):
        if requests and notifications:
            break
        await asyncio.sleep(0.01)

    return {
        "request": requests[0] if requests else None,
        "notification": notifications[0] if notifications else None,
    }


async def neighbour_diagnostic_pulls(module, inter_file):
    logic_cls = module.logic_class()
    server = sys.modules["rassumfrassum.frassum"].Server()
    server.name = "tsgo"
    server.caps = {"diagnosticProvider": {"interFileDependencies": inter_file}}
    origin = types.SimpleNamespace(docver=1, inflight_pulls={})
    neighbour = types.SimpleNamespace(docver=1, inflight_pulls={})
    requests = []
    notifications = []

    async def request_server(_server, method, params):
        requests.append(params["textDocument"]["uri"])
        return False, {"kind": "unchanged", "resultId": "1"}

    async def notify_client(method, params):
        notifications.append(params["uri"])

    logic = logic_cls.__new__(logic_cls)
    logic.servers = {id(server): server}
    logic.request_server = request_server
    logic.notify_client = notify_client
    logic.documents = {"file:///x.ts": origin, "file:///y.ts": neighbour}
    logic._stash_diagnostics_data = lambda _diags, _server, _state: None

    await logic._pull_and_stream_diags("file:///x.ts", origin, True)
    for _ in range(5):
        await asyncio.sleep(0.01)

    return {
        "requested": sorted(requests),
        "notified": sorted(notifications),
    }


async def initialize_options_by_server(module):
    """Return the initializationOptions each server receives."""
    servers = []
    for index, command in enumerate(module.SERVERS):
        server = sys.modules["rassumfrassum.frassum"].Server()
        base = os.path.basename(command[0])
        server.name = f"{base}#{index}" if index else base
        servers.append(server)
    logic = module.logic_class().__new__(module.logic_class())
    params = {"initializationOptions": {}}
    await logic.on_client_request("initialize", params, servers)
    return [
        logic.process_request("initialize", params, server).get(
            "initializationOptions"
        )
        for server in servers
    ]


async def unsupported_registration_response(module):
    logic_cls = module.logic_class()
    server = sys.modules["rassumfrassum.frassum"].Server()
    server.name = "tsgo"
    logic = logic_cls.__new__(logic_cls)
    response = await logic.on_server_request(
        "client/registerCapability",
        {
            "registrations": [
                {
                    "method": "workspace/didChangeWatchedFiles",
                    "registerOptions": {"watchers": []},
                }
            ]
        },
        server,
    )
    return response.payload if response else "forward"


def main():
    module = load_module(sys.argv[1])
    server_kind = {
        "astro-ls": module._server_kind("astro-ls"),
        "biome": module._server_kind("biome"),
        "deno": module._server_kind("deno"),
        "eslint": module._server_kind("eslint"),
        "eslint-language-server": module._server_kind("eslint-language-server"),
        "vscode-eslint-language-server": module._server_kind(
            "vscode-eslint-language-server"
        ),
        "oxfmt": module._server_kind("oxfmt"),
        "oxlint": module._server_kind("oxlint"),
        "tailwindcss-language-server": module._server_kind(
            "tailwindcss-language-server"
        ),
        "tsgo": module._server_kind("tsgo"),
        "typescript-language-server": module._server_kind(
            "typescript-language-server"
        ),
        "vscode-css-language-server": module._server_kind(
            "vscode-css-language-server"
        ),
        "vue-language-server": module._server_kind("vue-language-server"),
        "unknown": module._server_kind("custom-lsp"),
    }

    print(
        json.dumps(
            {
                "serverKind": server_kind,
                "diffChangesFailures": diff_changes_failures(module),
                "diffChangesInstalled": sys.modules[
                    "rassumfrassum.frassum"
                ]._diff_changes
                is module._diff_changes,
                "servers": module.servers(),
                "hasLogicClass": hasattr(module, "logic_class"),
                "eslintLogic": module.ESLINT_LOGIC,
                "initOptions": module.INIT_OPTIONS,
                "eslintConfig": module._eslint_config(),
                "initializeOptionsByServer": asyncio.run(
                    initialize_options_by_server(module)
                ),
                "diagnosticPullRequest": asyncio.run(
                    diagnostic_pull_request(module)
                ),
                "neighbourPulls": asyncio.run(
                    neighbour_diagnostic_pulls(module, True)
                ),
                "neighbourPullsSingleFile": asyncio.run(
                    neighbour_diagnostic_pulls(module, False)
                ),
                "unsupportedRegistrationResponse": asyncio.run(
                    unsupported_registration_response(module)
                ),
            }
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
