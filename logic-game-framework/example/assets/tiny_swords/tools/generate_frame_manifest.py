from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "frame_manifest.json"

OVERRIDES: list[dict[str, Any]] = [
    {
        "path": "units/knights/dead/Dead.png",
        "frame": [128, 128],
        "method": "override_dead_128_grid",
        "sequences": [
            {"name": "Dead", "indices": [0, 1, 2, 3, 4, 5, 6], "loop": False},
            {"name": "Buried", "indices": [7, 8, 9, 10, 11, 12, 13], "loop": False},
        ],
    },
    {"prefix": "units/knights/lancer/", "frame": [320, 320], "method": "override_lancer_320_strip"},
    {"prefix": "units/", "frame": [192, 192], "method": "override_units_192_grid"},
    {
        "prefix": "scene_objects/devices/barrel/",
        "size": [768, 768],
        "frame": [128, 128],
        "method": "override_barrel_128_grid",
        "sequences": [
            {"name": "Idle_In", "indices": [0], "loop": True},
            {"name": "Out", "indices": [6, 7, 8, 9, 10, 11], "loop": False},
            {"name": "Idle_Out", "indices": [12], "loop": True},
            {"name": "In", "indices": [18, 19, 20, 21, 22, 23], "loop": False},
            {"name": "Run", "indices": [24, 25, 26], "loop": True},
            {"name": "Fired", "indices": [30, 31, 32], "loop": False},
        ],
    },
    {
        "prefix": "scene_objects/devices/tnt/",
        "frame": [192, 192],
        "method": "override_tnt_192_grid",
        "sequences": [
            {"name": "Idle", "indices": [0, 1, 2, 3, 4, 5], "loop": True},
            {"name": "Run", "indices": [7, 8, 9, 10, 11, 12], "loop": True},
            {"name": "Throw", "indices": [14, 15, 16, 17, 18, 19, 20], "loop": False},
        ],
    },
    {
        "path": "scene_objects/resources/wood/trees/Tree.png",
        "frame": [192, 192],
        "method": "override_tree_state_192_grid",
        "sequences": [
            {"name": "Idle", "indices": [0, 1, 2, 3], "loop": True},
            {"name": "Hit", "indices": [4, 5], "loop": False},
            {"name": "Stump", "indices": [8], "loop": False},
        ],
    },
    {"prefix": "scene_objects/resources/wood/trees/Tree1", "frame": [192, 256], "method": "override_tree_192x256_strip"},
    {"prefix": "scene_objects/resources/wood/trees/Tree2", "frame": [192, 256], "method": "override_tree_192x256_strip"},
    {"prefix": "scene_objects/resources/wood/trees/Tree3", "frame": [192, 192], "method": "override_tree_192_strip"},
    {"prefix": "scene_objects/resources/wood/trees/Tree4", "frame": [192, 192], "method": "override_tree_192_strip"},
    {
        "path": "scene_objects/resources/food/sheep/HappySheep_Idle.png",
        "frame": [128, 128],
        "method": "override_happy_sheep_idle_128_strip",
        "sequences": [
            {"name": "Idle", "indices": [0, 1, 2, 3, 4, 5, 6, 7], "loop": True},
        ],
    },
    {
        "path": "scene_objects/resources/food/sheep/HappySheep_Bouncing.png",
        "frame": [128, 128],
        "method": "override_happy_sheep_bouncing_128_strip",
        "sequences": [
            {"name": "Bouncing", "indices": [0, 1, 2, 3, 4, 5], "loop": True},
        ],
    },
    {
        "path": "effects/environment/dust/Dust_01.png",
        "frame": [64, 64],
        "method": "override_dust_64_strip",
        "sequences": [
            {"name": "Dust_01", "indices": [0, 1, 2, 3, 4, 5, 6, 7], "loop": False},
        ],
    },
    {
        "path": "effects/environment/dust/Dust_02.png",
        "frame": [64, 64],
        "method": "override_dust_64_strip",
        "sequences": [
            {"name": "Dust_02", "indices": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "loop": False},
        ],
    },
    {
        "path": "scene_objects/resources/gold/pickup/Gold_Pickup_Spawn.png",
        "frame": [128, 128],
        "method": "override_resource_spawn_128_strip",
        "sequences": [
            {"name": "Spawn", "indices": [0, 1, 2, 3, 4, 5, 6], "loop": False},
        ],
    },
    {
        "path": "scene_objects/resources/food/meat/pickup/Meat_Pickup_Spawn.png",
        "frame": [128, 128],
        "method": "override_resource_spawn_128_strip",
        "sequences": [
            {"name": "Spawn", "indices": [0, 1, 2, 3, 4, 5, 6], "loop": False},
        ],
    },
    {
        "path": "scene_objects/resources/wood/pickup/Wood_Pickup_Spawn.png",
        "frame": [128, 128],
        "method": "override_resource_spawn_128_strip",
        "sequences": [
            {"name": "Spawn", "indices": [0, 1, 2, 3, 4, 5, 6], "loop": False},
        ],
    },
    {"prefix": "scene_objects/buildings/goblins/wood_tower/Wood_Tower_", "size": [1024, 192], "frame": [256, 192], "method": "override_wood_tower_strip"},
    {"prefix": "scene_objects/resources/gold/mine/", "exclude": True, "method": "override_exclude_static_gold_mine"},
    {"path": "effects/environment/fire/Fire.png", "frame": [128, 128], "method": "override_fire_128_strip"},
    {"prefix": "effects/environment/fire/Fire_", "frame": [64, 64], "method": "override_fire_64_strip"},
]


def match_override(rel: str, width: int, height: int) -> dict[str, Any] | None:
    for rule in OVERRIDES:
        rule_path = rule.get("path")
        rule_prefix = rule.get("prefix")
        rule_size = rule.get("size")
        if rule_path is not None and rel != rule_path.lower():
            continue
        if rule_prefix is not None and not rel.startswith(str(rule_prefix).lower()):
            continue
        if rule_size is not None and [width, height] != rule_size:
            continue
        return rule
    return None


def infer_frame_size(path: Path, width: int, height: int) -> tuple[int, int, str, str, bool] | None:
    rel = path.relative_to(ROOT).as_posix().lower()
    override = match_override(rel, width, height)
    if override is not None:
        if override.get("exclude", False):
            return None
        frame = override["frame"]
        return frame[0], frame[1], override["method"], "override", False

    if rel.startswith("effects/") and width > height and width % height == 0:
        return height, height, "guessed_effect_square_strip", "guessed", True

    if rel.startswith("effects/") and width % 64 == 0 and height % 64 == 0:
        return 64, 64, "guessed_effect_64_grid", "guessed", True

    if rel.startswith("decor/") or rel.startswith("terrain/"):
        if width > height and width % height == 0:
            return height, height, "guessed_square_strip", "guessed", True

    if rel.startswith("scene_objects/resources/"):
        if width > height and width % height == 0:
            return height, height, "guessed_resource_square_strip", "guessed", True

    return None


def alpha_bbox(image: Image.Image, x: int, y: int, width: int, height: int) -> list[int] | None:
    alpha = image.crop((x, y, x + width, y + height)).getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return None
    left, top, right, bottom = bbox
    return [left, top, right - 1, bottom - 1]


def offsets(bbox: list[int], frame_w: int, frame_h: int) -> dict[str, list[float]]:
    left, top, right, bottom = bbox
    center_x = (left + right + 1) * 0.5
    center_y = (top + bottom + 1) * 0.5
    cell_center_x = frame_w * 0.5
    cell_center_y = frame_h * 0.5
    bottom_center_x = center_x
    bottom_center_y = float(bottom + 1)
    return {
        "visual_center_from_cell_center": [
            round(center_x - cell_center_x, 2),
            round(center_y - cell_center_y, 2),
        ],
        "bottom_center_from_cell_center": [
            round(bottom_center_x - cell_center_x, 2),
            round(bottom_center_y - cell_center_y, 2),
        ],
    }


def make_sequence(name: str, start: int, count: int, loop: bool = True) -> dict[str, Any]:
    return {"name": name, "indices": list(range(start, start + count)), "loop": loop}


def is_valid_frame(path: Path, bbox: list[int], frame_w: int, frame_h: int) -> bool:
    rel = path.relative_to(ROOT).as_posix().lower()
    left, top, right, bottom = bbox
    bbox_w = right - left + 1
    bbox_h = bottom - top + 1
    area_ratio = (bbox_w * bbox_h) / float(frame_w * frame_h)

    if rel.startswith("scene_objects/devices/barrel/"):
        if area_ratio < 0.03:
            return False
        if left == 0 and bbox_w < frame_w * 0.45:
            return False
        if right == frame_w - 1 and bbox_w < frame_w * 0.45:
            return False
    return True


def analyze_png(path: Path) -> dict[str, Any] | None:
    with Image.open(path) as raw:
        image = raw.convert("RGBA")
    width, height = image.size
    inferred = infer_frame_size(path, width, height)
    if inferred is None:
        return None

    frame_w, frame_h, method, confidence, needs_review = inferred
    cols = width // frame_w
    rows = height // frame_h
    if cols <= 1 or rows <= 0:
        return None

    frames: list[dict[str, Any]] = []
    row_counts: list[int] = []
    for row in range(rows):
        row_non_empty = 0
        for col in range(cols):
            bbox = alpha_bbox(image, col * frame_w, row * frame_h, frame_w, frame_h)
            if bbox is None:
                continue
            if not is_valid_frame(path, bbox, frame_w, frame_h):
                continue
            row_non_empty += 1
            frame_entry: dict[str, Any] = {
                "index": row * cols + col,
                "row": row,
                "col": col,
                "region": [col * frame_w, row * frame_h, frame_w, frame_h],
                "bbox": bbox,
            }
            frame_entry.update(offsets(bbox, frame_w, frame_h))
            frames.append(frame_entry)
        row_counts.append(row_non_empty)

    if len(frames) <= 1:
        return None

    rel = path.relative_to(ROOT).as_posix().lower()
    override = match_override(rel, width, height)
    sequences = override.get("sequences", []) if override is not None else []
    if not sequences and rel.startswith("units/knights/lancer/"):
        frame_indices = [frame["index"] for frame in frames]
        sequence_name = path.stem.replace("Lancer_", "")
        sequences = [{
            "name": sequence_name,
            "indices": frame_indices,
            "loop": True,
        }]
    elif not sequences and rel.startswith("units/knights/pawn/"):
        sequences = [
            make_sequence("Idle", 0, 6),
            make_sequence("Run", 6, 6),
            make_sequence("Build", 12, 6),
            make_sequence("Chop", 18, 6),
            make_sequence("Carry_Idle", 24, 6),
            make_sequence("Carry_Run", 30, 6),
        ]
    elif not sequences and rel.startswith("units/knights/warrior/"):
        sequences = [
            make_sequence("Idle", 0, 6),
            make_sequence("Run", 6, 6),
            make_sequence("Attack_Front_1", 12, 6),
            make_sequence("Attack_Front_2", 18, 6),
            make_sequence("Attack_Down_1", 24, 6),
            make_sequence("Attack_Down_2", 30, 6),
            make_sequence("Attack_Up_1", 36, 6),
            make_sequence("Attack_Up_2", 42, 6),
        ]
    elif not sequences and rel.startswith("units/knights/archer/"):
        sequences = [
            make_sequence("Idle", 0, 6),
            make_sequence("Run", 8, 6),
            make_sequence("Shoot_Up", 16, 8),
            make_sequence("Shoot_UpRight", 24, 8),
            make_sequence("Shoot_Right", 32, 8),
            make_sequence("Shoot_DownRight", 40, 8),
            make_sequence("Shoot_Down", 48, 8),
        ]

    return {
        "path": path.relative_to(ROOT).as_posix(),
        "image_size": [width, height],
        "frame_size": [frame_w, frame_h],
        "cols": cols,
        "rows": rows,
        "method": method,
        "confidence": confidence,
        "needs_review": needs_review,
        "non_empty_frame_count": len(frames),
        "row_non_empty_counts": row_counts,
        "sequences": sequences,
        "frames": frames,
    }


def main() -> None:
    entries: list[dict[str, Any]] = []
    for path in sorted(ROOT.rglob("*.png")):
        entry = analyze_png(path)
        if entry is not None:
            entries.append(entry)

    payload = {
        "root": "res://addons/logic-game-framework/example/assets/tiny_swords",
        "asset_count": len(entries),
        "entries": entries,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {OUT}")
    print(f"asset_count={len(entries)}")


if __name__ == "__main__":
    main()
