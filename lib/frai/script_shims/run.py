#!/usr/bin/env python3
# frozen_string_literal: true — Frai internal shim; do not edit in user projects.

import importlib.util
import json
import sys
from pathlib import Path


def main() -> None:
    path = Path(sys.argv[1])
    spec = importlib.util.spec_from_file_location(path.stem, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load script: {path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    if not hasattr(module, "call"):
        raise SystemExit(f"Script must define call(input): {path}")

    payload = json.load(sys.stdin)
    result = module.call(payload["input"])
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
