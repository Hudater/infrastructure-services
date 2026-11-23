"""Reuse locally installed Ollama GGUF layers by digest. Keep the cache read-only."""
import configparser
import json
import os
from pathlib import Path
import re
import sys

root, state = map(Path, sys.argv[1:])
preset = configparser.ConfigParser(interpolation=None)
preset["*"] = {"ctx-size": str(int(os.getenv("LLAMA_CONTEXT_SIZE", "16384"))), "parallel": "1"}
for manifest in sorted((root / "models/manifests/registry.ollama.ai/library").glob("*/*")):
    name = manifest.parent.name + ("" if manifest.name == "latest" else "-" + manifest.name)
    if not re.fullmatch(r"[\w.-]+", name):
        raise ValueError(f"Invalid model alias: {name}")
    options = {}
    for layer in json.loads(manifest.read_text())["layers"]:
        key = {"application/vnd.ollama.image.model": "model",
               "application/vnd.ollama.image.projector": "mmproj"}.get(layer["mediaType"])
        if key:
            digest = layer["digest"]
            if not re.fullmatch("sha256:[0-9a-f]{64}", digest):
                raise ValueError("Invalid model digest")
            blob = Path("models/blobs", digest.replace(":", "-"))
            with (root / blob).open("rb") as f:
                if f.read(4) != b"GGUF":
                    print(f"Skipping non-GGUF {key} in {name}", file=sys.stderr)
                    continue
            options[key] = "/weights/" + str(blob)
    if "model" in options:
        if "embedding" in name:
            options.update(embeddings="true", pooling="last")
        preset[name] = options
for row in Path(__file__).with_name("models.txt").read_text().splitlines():
    alias = row.split()[0]
    if alias == "inkling-vision" or not (root / "gguf" / (alias + ".gguf")).is_file():
        continue
    preset[alias] = {"model": f"/weights/gguf/{alias}.gguf"}
    if alias == "inkling-2-mini" and (root / "gguf/inkling-vision.gguf").is_file():
        preset[alias]["mmproj"] = "/weights/gguf/inkling-vision.gguf"
if len(preset.sections()) < 2:
    raise RuntimeError("No GGUF models found")
temp = state / "models.ini.tmp"
with temp.open("w") as f:
    preset.write(f)
os.replace(temp, state / "models.ini")
