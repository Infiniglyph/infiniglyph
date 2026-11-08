"""Live TED-RAG motion adapter. Stdlib only; no model or shell execution.

Retrieve authored motion constraints from numeric movement context, then use
the existing TED-RAG weighted constraint builder to synthesize bounded gains.
The general research corpus is not treated as authoritative animation data.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import time

LIMITS = {
    "pitch_gain": (0.6, 1.4), "yaw_gain": (0.6, 1.4),
    "bank_gain": (0.6, 1.4), "sway_gain": (0.6, 1.3),
    "settle_gain": (0.75, 1.5),
}
MOTION_WEIGHTS = {"boost": 3.0, "transition": 3.0, "propulsion": 4.0,
                  "repetition": 1.5, "reversal": 3.0, "impact": 3.0}


def load_builder(rag_root: Path):
    path = rag_root / "context_builder.py"
    spec = importlib.util.spec_from_file_location("infiniglyph_ted_context", path)
    if not spec or not spec.loader:
        raise ValueError("TED-RAG constraint builder unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module.build_fractal_constraint


def finite(value, low: float, high: float) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("Non-finite motion value")
    return min(high, max(low, number))


def decide(context: dict, corpus: dict, builder) -> dict:
    features = [finite(context.get("speed", 0), 0, 1),
                finite(context.get("acceleration", 0), -1, 1),
                finite(context.get("turn", 0), 0, 1),
                float(bool(context.get("grounded", True))),
                finite(context.get("landing", 0), 0, 1)]
    # Ground contact and impact must distinguish air/land from a similar speed.
    importance = [1.0, 1.5, 1.8, 4.0, 4.0]
    features.extend(finite(context.get(name, 0), 0, 1) for name in MOTION_WEIGHTS)
    importance.extend(MOTION_WEIGHTS.values())
    ranked = []
    for index, profile in enumerate(corpus["profiles"]):
        target = list(profile["features"])
        target.extend(finite(profile.get("motion", {}).get(name, 0), 0, 1) for name in MOTION_WEIGHTS)
        distance = sum(w * (a-b)**2 for w, a, b in zip(importance, features, target, strict=True))
        ranked.append((math.exp(-distance), {
            "source": "infiniglyph/data/motion_constraints.json#" + profile["id"],
            "chunk_id": index, "ted_role": "authored_motion_constraint",
            "ted_symbols": ["C(x)"], "profile": profile,
        }))
    ranked.sort(key=lambda item: item[0], reverse=True)
    weighted, summary = builder(ranked[:3], weight_floor=0.05)
    parameters = {}
    for name, (low, high) in LIMITS.items():
        parameters[name] = finite(sum(chunk["constraint"]["weight"] *
            finite(chunk["profile"]["parameters"][name], low, high)
            for _, chunk in weighted), low, high)
    return {"schema": 1, "engine": "TED-RAG/context_builder", "parameters": parameters,
            "profiles": [{"id": chunk["profile"]["id"],
                          "weight": chunk["constraint"]["weight"],
                          "source": chunk["source"]} for _, chunk in weighted],
            "constraint": summary, "theory_source": corpus["theory_source"]}


def decide_world(context: dict, corpus: dict, builder) -> dict:
    limits = {"near_range": (24, 32), "mid_hz": (15, 20), "far_hz": (8, 10)}
    features = [finite(context.get(name, 0), 0, 1) for name in ("speed", "crowd", "combat")]
    ranked = []
    for index, profile in enumerate(corpus["profiles"]):
        score = math.exp(-sum(w * (a-b)**2 for w, a, b in
            zip((1.5, 2.0, 4.0), features, profile["features"], strict=True)))
        ranked.append((score, {"source": "infiniglyph/data/world_constraints.json#" + profile["id"],
            "chunk_id": index, "ted_role": "authored_world_attention", "profile": profile}))
    ranked.sort(key=lambda item: item[0], reverse=True)
    weighted, summary = builder(ranked[:2], weight_floor=0.05)
    parameters = {name: finite(sum(chunk["constraint"]["weight"] *
        finite(chunk["profile"]["parameters"][name], *bounds) for _, chunk in weighted), *bounds)
        for name, bounds in limits.items()}
    return {"parameters": parameters, "profiles": [chunk["profile"]["id"] for _, chunk in weighted],
        "constraint": summary}


def serve(session: Path, corpus_path: Path, rag_root: Path) -> None:
    request_path, response_path = session / "request.json", session / "response.json"
    builder = load_builder(rag_root)
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    world_path = corpus_path.with_name("world_constraints.json")
    world_corpus = json.loads(world_path.read_text(encoding="utf-8")) if world_path.is_file() else None
    last_id = -1
    last_request = time.monotonic()
    while time.monotonic() - last_request < 4.0:
        if (session / "stop").exists():
            return
        try:
            request = json.loads(request_path.read_text(encoding="utf-8"))
            request_id = int(request["id"])
            if request_id != last_id:
                last_request = time.monotonic()
                result = decide(request["context"], corpus, builder)
                if world_corpus and request.get("world_context"):
                    result["world_attention"] = decide_world(request["world_context"], world_corpus, builder)
                result["id"] = request_id
                result["worker_pid"] = os.getpid()
                temporary = response_path.with_suffix(".tmp")
                temporary.write_text(json.dumps(result, allow_nan=False), encoding="utf-8")
                temporary.replace(response_path)
                last_id = request_id
        except (FileNotFoundError, PermissionError, json.JSONDecodeError):
            # Windows readers/atomic replacements can briefly hold either IPC
            # file. Retry the current request instead of terminating the helper.
            pass
        time.sleep(0.025)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--rag-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        serve(args.session.resolve(), args.corpus.resolve(), args.rag_root.resolve())
    except (OSError, ValueError, KeyError, TypeError) as error:
        (args.session / "error.txt").write_text(str(error), encoding="utf-8")
        raise SystemExit(1)
