# /// script
# requires-python = ">=3.9"
# dependencies = ["pyyaml"]
# ///
"""
Central YAML resource parser for LXC deploy scripts.

Usage:
  uv run parse.py <yaml_file>              # Output all keys as KEY=value (shell-safe)
  uv run parse.py <yaml_file> <key>        # Output single value
  uv run parse.py <yaml_file> --json       # Output as JSON
  uv run parse.py <yaml_file> --validate   # Validate against expected keys

Exit codes:
  0 = success
  1 = file not found / parse error
  2 = key not found (single-key mode)
"""

import json
import sys
from pathlib import Path

import yaml


def shell_escape(value: str) -> str:
    """Escape a value for safe shell assignment."""
    if value == "":
        return "''"
    # If value is simple (alphanumeric, dots, dashes, slashes, colons), no quoting needed
    safe_chars = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@")
    if all(c in safe_chars for c in str(value)):
        return str(value)
    # Otherwise single-quote it, escaping any embedded single quotes
    return "'" + str(value).replace("'", "'\\''") + "'"


def flatten(data: dict, prefix: str = "") -> dict[str, str]:
    """Flatten nested YAML into dot-separated keys with string values.

    Example:
      {network: {bridge: vmbr0, ip: dhcp}}
      becomes:
      {"network.bridge": "vmbr0", "network.ip": "dhcp"}
    """
    result = {}
    for key, value in data.items():
        full_key = f"{prefix}{key}" if not prefix else f"{prefix}.{key}"
        if isinstance(value, dict):
            result.update(flatten(value, full_key))
        elif isinstance(value, list):
            # Lists become space-separated strings for shell arrays
            result[full_key] = " ".join(str(item) for item in value)
        elif isinstance(value, bool):
            result[full_key] = "true" if value else "false"
        elif value is None:
            result[full_key] = ""
        else:
            result[full_key] = str(value)
    return result


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 1

    yaml_file = Path(sys.argv[1])
    if not yaml_file.exists():
        print(f"error: file not found: {yaml_file}", file=sys.stderr)
        return 1

    try:
        data = yaml.safe_load(yaml_file.read_text())
    except yaml.YAMLError as e:
        print(f"error: failed to parse YAML: {e}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print("error: YAML root must be a mapping", file=sys.stderr)
        return 1

    flat = flatten(data)

    # --json: output as JSON object
    if "--json" in sys.argv:
        print(json.dumps(flat, indent=2))
        return 0

    # --validate: just check the file parses, output nothing
    if "--validate" in sys.argv:
        return 0

    # Single key lookup
    remaining = [a for a in sys.argv[2:] if not a.startswith("--")]
    if remaining:
        key = remaining[0]
        if key in flat:
            print(flat[key])
            return 0
        # Also try with underscores converted to dots for convenience
        dotted = key.replace("_", ".")
        if dotted in flat:
            print(flat[dotted])
            return 0
        print(f"error: key not found: {key}", file=sys.stderr)
        return 2

    # All keys: output as shell-safe KEY=value (dots become underscores for shell compat)
    for key, value in flat.items():
        shell_key = key.replace(".", "_").replace("-", "_").upper()
        print(f"{shell_key}={shell_escape(value)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
