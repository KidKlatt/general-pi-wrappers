#!/usr/bin/env python3
"""Build catalog.json from games/*/game.json, or check that it is current.

    python tools/build-catalog.py           rewrite catalog.json
    python tools/build-catalog.py --check   exit 1 if catalog.json is stale or a game.json is invalid

catalog.json is the index general-pi-manager reads (README, "Catalog").
Only the standard library is used; the checks are the essentials of schema/game.schema.json.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATUSES = {"planned", "in-progress", "playable", "released", "retired"}
STANDARD_SETUP_OPTIONS = ("--installer", "--home", "--allow-upgrades", "--no-desktop", "--jobs", "--check")
RATINGS = {None, "smooth", "playable", "rough", "broken"}
CATALOG_VERSION = 2
MIN_MANAGER_VERSION = "0.2.0"   # raise when the catalog changes in a way older managers cannot read


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
    out += interface_problems(game.get("entry_points", {}), ROOT / "games" / folder)
    out += info_problems(game)
    return out


def info_problems(game: dict) -> list[str]:
    """targets / notes / requirements: what the manager shows (README, "Catalog")."""
    out = []
    for i, t in enumerate(game.get("targets", [])):
        fps = t.get("fps")
        if not isinstance(fps, dict):
            out.append(f"targets[{i}].fps must be an object (typical, low, scene)")
        else:
            for k in ("typical", "low"):
                if fps.get(k) is not None and not isinstance(fps[k], (int, float)):
                    out.append(f"targets[{i}].fps.{k} must be a number or null")
        if t.get("rating") not in RATINGS:
            out.append(f"targets[{i}].rating must be one of {sorted(r for r in RATINGS if r)} or null")
        if not isinstance(t.get("tested", []), list):
            out.append(f"targets[{i}].tested must be a list")
    notes = game.get("notes", {})
    if not isinstance(notes.get("summary"), str) or not notes.get("summary"):
        out.append("notes.summary is missing")
    for k in ("known_issues", "tips"):
        if not isinstance(notes.get(k, []), list):
            out.append(f"notes.{k} must be a list")
    if not isinstance(game.get("requirements", {}).get("disk_gb"), (int, float)):
        out.append("requirements.disk_gb is missing")
    return out


ARG = r"--[a-z0-9-]+(=[A-Za-z0-9._:+-]+)?"
NAME = r"[a-z0-9]+(-[a-z0-9]+)*"


def option_problems(opts, where: str, script: str | None) -> list[str]:
    """README "Options": flags (checkboxes) and choices (drop-downs). Every --name must appear
    in the script that takes it, so an option cannot be announced that the script rejects."""
    if not isinstance(opts, list):
        return [f"{where} must be a list"]
    out, keys, args = [], set(), []
    for o in opts:
        if not isinstance(o, dict):
            out.append(f"{where}: each entry must be an object")
            continue
        kind = o.get("type", "flag")
        if kind == "flag":
            if not (re.fullmatch(r"--[a-z0-9-]+", str(o.get("option", ""))) and o.get("help")):
                out.append(f"{where}: a flag needs option (--name) and help")
                continue
            key = o["option"]
            args.append(key)
        elif kind == "choice":
            key = str(o.get("id", ""))
            choices = o.get("choices")
            if not (re.fullmatch(NAME, key) and o.get("label") and isinstance(choices, list) and len(choices) >= 2):
                out.append(f"{where}: a choice needs id, label and at least two choices")
                continue
            values = []
            for c in choices:
                if not (isinstance(c, dict) and re.fullmatch(NAME, str(c.get("value", ""))) and c.get("label")
                        and isinstance(c.get("args"), list) and all(re.fullmatch(ARG, str(a)) for a in c["args"])):
                    out.append(f"{where}.{key}: each choice needs value, label and args (--name or --name=value)")
                    continue
                values.append(c["value"])
                args += c["args"]
            if len(set(values)) != len(values):
                out.append(f"{where}.{key}: choice values must differ")
            if o.get("default") not in values:
                out.append(f"{where}.{key}: default must be one of the choice values")
        else:
            out.append(f"{where}: type must be flag or choice, not {kind}")
            continue
        if key in keys:
            out.append(f"{where}: {key} listed twice")
        keys.add(key)
    if script is not None:
        for a in sorted({a.split("=")[0] for a in args}):
            if a not in script:
                out.append(f"{where}: {a} is not in the script")
    return out


def interface_problems(ep: dict, folder: Path) -> list[str]:
    """The standard setup interface (README, "Setup interface"), version 1."""
    out = []
    for key in ("setup_options", "play_options"):
        script = folder / ("scripts/pi/setup.sh" if key == "setup_options" else "scripts/pi/play.sh")
        out += option_problems(ep.get(key, []), f"entry_points.{key}",
                               script.read_text(encoding="utf-8") if script.is_file() else None)
    if ep.get("setup_interface") is None:
        return out
    if ep.get("setup_interface") != 1:
        out.append("entry_points.setup_interface must be 1")
    if ep.get("setup") != "scripts/pi/setup.sh":
        out.append("entry_points.setup must be scripts/pi/setup.sh with setup_interface")
    if ep.get("uninstall") not in (None, "scripts/pi/uninstall.sh"):
        out.append("entry_points.uninstall must be scripts/pi/uninstall.sh (or absent)")
    for key in ("setup", "play", "uninstall"):
        if ep.get(key) and not (folder / ep[key]).is_file():
            out.append(f"entry_points.{key}: {ep[key]} not found")
    script = folder / "scripts/pi/setup.sh"
    if script.is_file():
        text = script.read_text(encoding="utf-8")
        for opt in STANDARD_SETUP_OPTIONS:
            if f"{opt})" not in text:
                out.append(f"setup.sh does not accept {opt}")
        if "SUDO_ASKPASS" not in text or re.search(r"(?m)^(?!\s*#).*(?<![\w-])sudo (apt|true)", text):
            out.append("setup.sh must run sudo through sudo_ (sudo -A when SUDO_ASKPASS is set)")
    for d in ep.get("desktop", []):
        p = folder / d
        if p.is_file() and "/home/" in p.read_text(encoding="utf-8"):
            out.append(f"{d}: use @GAME_HOME@ instead of a /home/ path")
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
        version = game.get("wrapper", {}).get("version")
        ep = game.get("entry_points", {})
        notes = game.get("notes", {})
        games.append({
            "slug": game.get("slug"),
            "short_id": game.get("short_id"),
            "title": game.get("title"),
            "path": f"games/{folder}",
            "wrapper_version": version,
            # The game folder at this version: the tag made when the version is merged to main.
            "tag": f"{folder}/v{version}",
            "status": game.get("wrapper", {}).get("status"),
            "min_manager_version": MIN_MANAGER_VERSION,
            "setup_interface": ep.get("setup_interface"),
            "uninstall": bool(ep.get("uninstall")),
            "summary": notes.get("summary"),
            "known_issues": len(notes.get("known_issues", [])),
            "requirements": game.get("requirements"),
            "performance": [
                {
                    "device": t.get("device"),
                    "ram_gb": t.get("ram_gb"),
                    "config": t.get("config"),
                    "fps_typical": (t.get("fps") or {}).get("typical"),
                    "fps_low": (t.get("fps") or {}).get("low"),
                    "rating": t.get("rating"),
                }
                for t in game.get("targets", [])
            ],
            "products": [
                {
                    "product_id": str(p.get("product_id")),
                    "title": p.get("title"),
                    "gog_build_id": p.get("gog_build_id"),
                    "gog_installer_build": p.get("installer", {}).get("gog_installer_build"),
                    "files": p.get("installer", {}).get("files", []),
                }
                for p in game.get("gog_products", [])
            ],
        })
    return {"catalog_version": CATALOG_VERSION, "games": games}, errors


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
