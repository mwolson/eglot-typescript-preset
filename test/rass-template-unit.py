#!/usr/bin/env python3

import asyncio
import importlib.util
import json
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

        def process_request(self, method, params, server):
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
    frassum.LspLogic = LspLogic
    frassum.Server = Server
    json_mod.JSON = dict
    util.dmerge = dmerge

    sys.modules.setdefault("rassumfrassum", package)
    sys.modules["rassumfrassum.frassum"] = frassum
    sys.modules["rassumfrassum.json"] = json_mod
    sys.modules["rassumfrassum.util"] = util


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


async def neighbour_diagnostic_pulls(module, inter_file, legacy_attr):
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
    documents = {"file:///x.ts": origin, "file:///y.ts": neighbour}
    if legacy_attr:
        logic.document_state = documents
    else:
        logic.documents = documents
    logic._stash_diagnostics_data = lambda _diags, _server, _state: None

    await logic._pull_and_stream_diags("file:///x.ts", origin, True)
    for _ in range(5):
        await asyncio.sleep(0.01)

    return {
        "requested": sorted(requests),
        "notified": sorted(notifications),
    }


def process_request_returns_params(module):
    logic_cls = module.logic_class()
    server = sys.modules["rassumfrassum.frassum"].Server()
    server.name = "primary"
    logic = logic_cls.__new__(logic_cls)
    logic.primary = server
    params = {"textDocument": {"uri": "file:///x.ts"}}
    return logic.process_request("textDocument/hover", params, server) is params


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

    init_options_scoping = None
    if module.INIT_OPTIONS and hasattr(module, "logic_class"):
        logic_cls = module.logic_class()
        primary = sys.modules["rassumfrassum.frassum"].Server()
        primary.name = "primary"
        secondary = sys.modules["rassumfrassum.frassum"].Server()
        secondary.name = "secondary"
        logic = logic_cls.__new__(logic_cls)
        logic.primary = primary

        primary_params = logic.process_request(
            "initialize", {"initializationOptions": {}}, primary
        )
        primary_got = (primary_params or {}).get("initializationOptions", {})

        secondary_params = logic.process_request(
            "initialize", {"initializationOptions": {}}, secondary
        )
        secondary_got = (secondary_params or {}).get(
            "initializationOptions", {}
        )

        init_options_scoping = {
            "primaryGotOptions": bool(primary_got),
            "secondaryGotOptions": bool(secondary_got),
        }

    print(
        json.dumps(
            {
                "serverKind": server_kind,
                "servers": module.servers(),
                "hasLogicClass": hasattr(module, "logic_class"),
                "eslintLogic": module.ESLINT_LOGIC,
                "initOptions": module.INIT_OPTIONS,
                "initOptionsScoping": init_options_scoping,
                "diagnosticPullRequest": asyncio.run(
                    diagnostic_pull_request(module)
                ),
                "neighbourPulls": asyncio.run(
                    neighbour_diagnostic_pulls(module, True, False)
                ),
                "neighbourPullsLegacyAttr": asyncio.run(
                    neighbour_diagnostic_pulls(module, True, True)
                ),
                "neighbourPullsSingleFile": asyncio.run(
                    neighbour_diagnostic_pulls(module, False, False)
                ),
                "processRequestReturnsParams": process_request_returns_params(
                    module
                ),
                "unsupportedRegistrationResponse": asyncio.run(
                    unsupported_registration_response(module)
                ),
            }
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
