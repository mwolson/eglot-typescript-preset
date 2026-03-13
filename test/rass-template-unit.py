#!/usr/bin/env python3

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
        pass

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


def main():
    module = load_module(sys.argv[1])
    server_kind = {
        "astro-ls": module._server_kind("astro-ls"),
        "biome": module._server_kind("biome"),
        "eslint": module._server_kind("eslint"),
        "eslint-language-server": module._server_kind("eslint-language-server"),
        "vscode-eslint-language-server": module._server_kind(
            "vscode-eslint-language-server"
        ),
        "oxfmt": module._server_kind("oxfmt"),
        "oxlint": module._server_kind("oxlint"),
        "typescript-language-server": module._server_kind(
            "typescript-language-server"
        ),
        "unknown": module._server_kind("custom-lsp"),
    }

    print(
        json.dumps(
            {
                "serverKind": server_kind,
                "servers": module.servers(),
                "hasLogicClass": hasattr(module, "logic_class"),
                "eslintLogic": module.ESLINT_LOGIC,
                "astroInitOptions": module.ASTRO_INIT_OPTIONS,
            }
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
