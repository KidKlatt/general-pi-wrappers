#!/usr/bin/env python3
"""Build catalog.json from games/*/game.json, or check that it is current.

    python tools/build-catalog.py           rewrite catalog.json
    python tools/build-catalog.py --check   exit 1 if catalog.json is stale or a game.json is invalid

catalog.json is the index the future entry tool reads: GOG product id -> wrapper folder.
Only the standard library is used; the checks are the essentials of schema/game.schema.json.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATUSES = {"planned", "in-progress", "playable", "released", "retired"}


def problems(game: dict, folder: str) -> list[str]:
    out = []
    for key in ("schema_version", "slug", "short_id", "title", "wrapper", "gog_products"):
        if key not in game:
            out.append(f"missing {key}")
    if out:
        return out
    if game["slug"] != folder:
        out.append(f"slug {game['slug']!r} does not match folder {folder!r}")
    w = game["wrapper"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", w.get("version", "")):
        out.append("wrapper.version is not semver")
    if w.get("status") not in STATUSES:
        out.append(f"wrapper.status must be one of {sorted(STATUSES)}")
    for p in game["gog_products"]:
        if not re.fullmatch(r"\d+", str(p.get("product_id", ""))):
            out.append(f"product_id {p.get('product_id')!r} is not numeric")
        for f in p.get("installer", {}).get("files", []):
            if not re.fullmatch(r"[0-9a-f]{64}", f.get("sha256", "")):
                out.append(f"bad sha256 for {f.get('name')}")
    return out


def build() -> tuple[dict, list[str]]:
    games, errors, seen = [], [], {}
    for path in sorted(ROOT.glob("games/*/game.json")):
        folder = path.parent.name
        try:
            game = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errors.append(f"{folder}: {e}")
            continue
        errors += [f"{folder}: {p}" for p in problems(game, folder)]
        for p in game.get("gog_products", []):
            pid = str(p.get("product_id"))
            if pid in seen:
                errors.append(f"{folder}: product {pid} already claimed by {seen[pid]}")
            seen[pid] = folder
        games.append({
            "slug": game.get("slug"),
            "short_id": game.get("short_id"),
            "title": game.get("title"),
            "path": f"games/{folder}",
            "wrapper_version": game.get("wrapper", {}).get("version"),
            "status": game.get("wrapper", {}).get("status"),
            "products": [
                {
                    "product_id": str(p.get("product_id")),
                    "title": p.get("title"),
                    "gog_build_id": p.get("gog_build_id"),
                    "gog_installer_build": p.get("installer", {}).get("gog_installer_build"),
                }
                for p in game.get("gog_products", [])
            ],
        })
    return {"catalog_version": 1, "games": games}, errors


def main() -> int:
    catalog, errors = build()
    for e in errors:
        print("ERROR", e, file=sys.stderr)
    text = json.dumps(catalog, indent=2) + "\n"
    target = ROOT / "catalog.json"
    if "--check" in sys.argv:
        current = target.read_text(encoding="utf-8") if target.exists() else ""
        if current != text:
            print("catalog.json is stale: run python tools/build-catalog.py", file=sys.stderr)
            return 1
        return 1 if errors else 0
    if errors:
        return 1
    target.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {target.name}: {len(catalog['games'])} games")
    return 0


if __name__ == "__main__":
    sys.exit(main())
