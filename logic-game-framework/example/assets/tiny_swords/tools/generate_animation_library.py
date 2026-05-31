from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "animation_library.json"

DIRECTIONS = [
    "south",
    "south_east",
    "east",
    "north_east",
    "north",
    "north_west",
    "west",
    "south_west",
]

TEAM_COLORS = ["Blue", "Purple", "Red", "Yellow"]
LANCER_COLORS = ["Black", "Blue", "Purple", "Red", "Yellow"]


def manifest_sequence(
    name: str,
    path: str,
    manifest_name: str,
    *,
    direction: str = "",
    animation: str = "",
    loop: bool = True,
    fps: float = 8.0,
    flip_h: bool = False,
    source_direction: str = "",
    direction_mode: str = "",
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "name": name,
        "path": path,
        "manifest_sequence": manifest_name,
        "loop": loop,
        "fps": fps,
    }
    if direction:
        payload["direction"] = direction
    if animation:
        payload["animation"] = animation
    if flip_h:
        payload["flip_h"] = True
    if source_direction:
        payload["source_direction"] = source_direction
    if direction_mode:
        payload["direction_mode"] = direction_mode
    return payload


def image_sequence(
    name: str,
    path: str,
    *,
    animation: str = "",
    loop: bool = True,
    fps: float = 1.0,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "name": name,
        "path": path,
        "type": "image",
        "loop": loop,
        "fps": fps,
    }
    if animation:
        payload["animation"] = animation
    return payload


def entry(
    item_id: str,
    label: str,
    category: str,
    kind: str,
    sequences: list[dict[str, Any]],
    *,
    direction_mode: str = "",
    notes: str = "",
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": item_id,
        "label": label,
        "category": category,
        "kind": kind,
        "sequences": sequences,
    }
    if direction_mode:
        payload["direction_mode"] = direction_mode
    if notes:
        payload["notes"] = notes
    return payload


def add_resources(items: list[dict[str, Any]]) -> None:
    items.append(entry("resource/gold_mine", "Resource / Gold Mine", "resource", "gold_mine", [
        image_sequence("active", "scene_objects/resources/gold/mine/GoldMine_Active.png", animation="active"),
        image_sequence("inactive", "scene_objects/resources/gold/mine/GoldMine_Inactive.png", animation="inactive"),
        image_sequence("destroyed", "scene_objects/resources/gold/mine/GoldMine_Destroyed.png", animation="destroyed"),
    ]))
    items.append(entry("resource/gold_pickup", "Resource / Gold Pickup", "resource", "gold_pickup", [
        image_sequence("idle", "scene_objects/resources/gold/pickup/Gold_Pickup_Idle.png", animation="idle"),
        image_sequence("idle_no_shadow", "scene_objects/resources/gold/pickup/Gold_Pickup_Idle_NoShadow.png", animation="idle"),
        manifest_sequence("spawn", "scene_objects/resources/gold/pickup/Gold_Pickup_Spawn.png", "Spawn", animation="spawn"),
    ]))
    items.append(entry("resource/tree", "Resource / Tree", "resource", "tree", [
        manifest_sequence("idle", "scene_objects/resources/wood/trees/Tree.png", "Idle", animation="idle"),
        manifest_sequence("hit", "scene_objects/resources/wood/trees/Tree.png", "Hit", animation="hit"),
        manifest_sequence("stump", "scene_objects/resources/wood/trees/Tree.png", "Stump", animation="stump"),
    ]))
    for index in range(1, 5):
        frame_h = 256 if index <= 2 else 192
        items.append(entry(f"resource/tree_{index}", f"Resource / Tree {index}", "resource", "tree", [
            manifest_sequence("idle", f"scene_objects/resources/wood/trees/Tree{index}.png", f"Tree{index}", animation="idle"),
            image_sequence("stump", f"scene_objects/resources/wood/stumps/Stump_{index}.png", animation="stump"),
        ], notes=f"Free Pack tree variant, idle strip frame height {frame_h}."))
    items.append(entry("resource/wood_pickup", "Resource / Wood Pickup", "resource", "wood_pickup", [
        image_sequence("idle", "scene_objects/resources/wood/pickup/Wood_Pickup_Idle.png", animation="idle"),
        image_sequence("idle_no_shadow", "scene_objects/resources/wood/pickup/Wood_Pickup_Idle_NoShadow.png", animation="idle"),
        manifest_sequence("spawn", "scene_objects/resources/wood/pickup/Wood_Pickup_Spawn.png", "Spawn", animation="spawn"),
    ]))
    items.append(entry("resource/sheep_free_pack", "Resource / Sheep / Free Pack", "resource", "sheep", [
        manifest_sequence("idle", "scene_objects/resources/food/sheep/Sheep_Idle.png", "Sheep_Idle", animation="idle"),
        manifest_sequence("graze", "scene_objects/resources/food/sheep/Sheep_Grass.png", "Sheep_Grass", animation="graze"),
        manifest_sequence("move", "scene_objects/resources/food/sheep/Sheep_Move.png", "Sheep_Move", animation="move"),
    ]))
    items.append(entry("resource/happy_sheep", "Resource / Happy Sheep", "resource", "happy_sheep", [
        manifest_sequence("idle", "scene_objects/resources/food/sheep/HappySheep_Idle.png", "Idle", animation="idle"),
        manifest_sequence("bounce", "scene_objects/resources/food/sheep/HappySheep_Bouncing.png", "Bouncing", animation="bounce"),
    ]))
    items.append(entry("resource/meat_pickup", "Resource / Meat Pickup", "resource", "meat_pickup", [
        image_sequence("idle", "scene_objects/resources/food/meat/pickup/Meat_Pickup_Idle.png", animation="idle"),
        image_sequence("idle_no_shadow", "scene_objects/resources/food/meat/pickup/Meat_Pickup_Idle_NoShadow.png", animation="idle"),
        manifest_sequence("spawn", "scene_objects/resources/food/meat/pickup/Meat_Pickup_Spawn.png", "Spawn", animation="spawn"),
    ]))


def add_buildings(items: list[dict[str, Any]]) -> None:
    for faction, kinds in {
        "knights": ["castle", "house", "tower"],
        "goblins": ["wood_house", "wood_tower"],
    }.items():
        for kind in kinds:
            prefix = {
                "castle": "Castle",
                "house": "House",
                "tower": "Tower",
                "wood_house": "Goblin_House",
                "wood_tower": "Wood_Tower",
            }[kind]
            base_path = f"scene_objects/buildings/{faction}/{kind}"
            sequences: list[dict[str, Any]] = []
            for color in TEAM_COLORS:
                candidate = f"{base_path}/{prefix}_{color}.png"
                if (ROOT / candidate).exists():
                    if kind == "wood_tower":
                        sequences.append(manifest_sequence(color.lower(), candidate, f"{prefix}_{color}", animation="idle"))
                    else:
                        sequences.append(image_sequence(color.lower(), candidate, animation=color.lower()))
            for state, suffix in [("construction", "Construction"), ("in_construction", "InConstruction"), ("destroyed", "Destroyed")]:
                candidate = f"{base_path}/{prefix}_{suffix}.png"
                if (ROOT / candidate).exists():
                    sequences.append(image_sequence(state, candidate, animation=state))
            plain = f"{base_path}/{prefix}.png"
            if (ROOT / plain).exists():
                sequences.insert(0, image_sequence("idle", plain, animation="idle"))
            if sequences:
                items.append(entry(f"building/{faction}/{kind}", f"Building / {faction} / {kind}", "building", kind, sequences))


def add_direction_fallbacks(
    sequences: list[dict[str, Any]],
    path: str,
    animations: list[tuple[str, str]],
    *,
    direction_mode: str,
) -> None:
    for direction in DIRECTIONS:
        for animation, manifest_name in animations:
            sequences.append(manifest_sequence(
                f"{direction}/{animation}",
                path,
                manifest_name,
                direction=direction,
                animation=animation,
                source_direction="south",
                direction_mode=direction_mode,
            ))


def should_flip_single_facing(direction: str) -> bool:
    return direction in {"north_west", "west", "south_west"}


def add_worker_units(items: list[dict[str, Any]]) -> None:
    animations = [
        ("idle", "Idle"),
        ("run", "Run"),
        ("build", "Build"),
        ("chop", "Chop"),
        ("carry_idle", "Carry_Idle"),
        ("carry_run", "Carry_Run"),
    ]
    for color in TEAM_COLORS:
        path = f"units/knights/pawn/Pawn_{color}.png"
        sequences: list[dict[str, Any]] = []
        for direction in DIRECTIONS:
            flip_h = should_flip_single_facing(direction)
            for animation, manifest_name in animations:
                sequences.append(manifest_sequence(
                    f"{direction}/{animation}",
                    path,
                    manifest_name,
                    direction=direction,
                    animation=animation,
                    flip_h=flip_h,
                    source_direction="single_source",
                    direction_mode="fallback_horizontal_flip",
                ))
        items.append(entry(
            f"unit/pawn/{color.lower()}",
            f"Unit / Pawn / {color}",
            "unit",
            "pawn",
            sequences,
            direction_mode="fallback_horizontal_flip",
            notes="Pawn has one facing in the source sheet; west-facing directions use horizontal flip.",
        ))


def add_warrior_units(items: list[dict[str, Any]]) -> None:
    attack_map = {
        "south": (["Attack_Down_1", "Attack_Down_2"], False, "south"),
        "south_east": (["Attack_Down_1", "Attack_Down_2"], False, "south"),
        "east": (["Attack_Front_1", "Attack_Front_2"], False, "east"),
        "north_east": (["Attack_Up_1", "Attack_Up_2"], False, "north"),
        "north": (["Attack_Up_1", "Attack_Up_2"], False, "north"),
        "north_west": (["Attack_Up_1", "Attack_Up_2"], True, "north"),
        "west": (["Attack_Front_1", "Attack_Front_2"], True, "east"),
        "south_west": (["Attack_Down_1", "Attack_Down_2"], True, "south"),
    }
    for color in TEAM_COLORS:
        path = f"units/knights/warrior/Warrior_{color}.png"
        sequences: list[dict[str, Any]] = []
        add_direction_fallbacks(sequences, path, [("idle", "Idle"), ("run", "Run")], direction_mode="shared_idle_run")
        for direction in DIRECTIONS:
            manifest_names, flip_h, source_direction = attack_map[direction]
            for index, manifest_name in enumerate(manifest_names, start=1):
                sequences.append(manifest_sequence(
                    f"{direction}/attack_{index}",
                    path,
                    manifest_name,
                    direction=direction,
                    animation=f"attack_{index}",
                    flip_h=flip_h,
                    source_direction=source_direction,
                    direction_mode="partial_directional_attack_variants",
                ))
        items.append(entry(
            f"unit/warrior/{color.lower()}",
            f"Unit / Warrior / {color}",
            "unit",
            "warrior",
            sequences,
            direction_mode="partial_directional_attack_variants",
        ))


def add_archer_units(items: list[dict[str, Any]]) -> None:
    shoot_map = {
        "south": ("Shoot_Down", False, "south"),
        "south_east": ("Shoot_DownRight", False, "south_east"),
        "east": ("Shoot_Right", False, "east"),
        "north_east": ("Shoot_UpRight", False, "north_east"),
        "north": ("Shoot_Up", False, "north"),
        "north_west": ("Shoot_UpRight", True, "north_east"),
        "west": ("Shoot_Right", True, "east"),
        "south_west": ("Shoot_DownRight", True, "south_east"),
    }
    for color in TEAM_COLORS:
        path = f"units/knights/archer/Archer_{color}.png"
        sequences: list[dict[str, Any]] = []
        add_direction_fallbacks(sequences, path, [("idle", "Idle"), ("run", "Run")], direction_mode="shared_idle_run")
        for direction in DIRECTIONS:
            manifest_name, flip_h, source_direction = shoot_map[direction]
            sequences.append(manifest_sequence(
                f"{direction}/shoot",
                path,
                manifest_name,
                direction=direction,
                animation="shoot",
                flip_h=flip_h,
                source_direction=source_direction,
                direction_mode="partial_directional_mirror",
            ))
        items.append(entry(
            f"unit/archer/{color.lower()}",
            f"Unit / Archer / {color}",
            "unit",
            "archer",
            sequences,
            direction_mode="partial_directional_mirror",
        ))


def add_lancer_units(items: list[dict[str, Any]]) -> None:
    direction_map = {
        "south": ("Down", False, "south"),
        "south_east": ("DownRight", False, "south_east"),
        "east": ("Right", False, "east"),
        "north_east": ("UpRight", False, "north_east"),
        "north": ("Up", False, "north"),
        "north_west": ("UpRight", True, "north_east"),
        "west": ("Right", True, "east"),
        "south_west": ("DownRight", True, "south_east"),
    }
    for color in LANCER_COLORS:
        sequences: list[dict[str, Any]] = []
        idle_path = f"units/knights/lancer/Lancer_{color}_Idle.png"
        run_path = f"units/knights/lancer/Lancer_{color}_Run.png"
        for direction in DIRECTIONS:
            sequences.append(manifest_sequence(
                f"{direction}/idle",
                idle_path,
                f"{color}_Idle",
                direction=direction,
                animation="idle",
                source_direction="south",
                direction_mode="shared_idle_run",
            ))
            sequences.append(manifest_sequence(
                f"{direction}/run",
                run_path,
                f"{color}_Run",
                direction=direction,
                animation="run",
                source_direction="south",
                direction_mode="shared_idle_run",
            ))
            source, flip_h, source_direction = direction_map[direction]
            attack_path = f"units/knights/lancer/Lancer_{color}_{source}_Attack.png"
            sequences.append(manifest_sequence(
                f"{direction}/attack",
                attack_path,
                f"{color}_{source}_Attack",
                direction=direction,
                animation="attack",
                flip_h=flip_h,
                source_direction=source_direction,
                direction_mode="partial_directional_mirror",
            ))
        items.append(entry(
            f"unit/lancer/{color.lower()}",
            f"Unit / Lancer / {color}",
            "unit",
            "lancer",
            sequences,
            direction_mode="partial_directional_mirror",
        ))


def add_units(items: list[dict[str, Any]]) -> None:
    add_worker_units(items)
    add_warrior_units(items)
    add_lancer_units(items)
    add_archer_units(items)
    items.append(entry("unit/common/dead", "Unit / Common Dead", "unit", "common_dead", [
        manifest_sequence("dead", "units/knights/dead/Dead.png", "Dead", animation="dead", loop=True),
        manifest_sequence("buried", "units/knights/dead/Dead.png", "Buried", animation="buried", loop=True),
    ]))


def main() -> None:
    accepted: list[dict[str, Any]] = []
    add_resources(accepted)
    add_buildings(accepted)
    add_units(accepted)

    payload = {
        "version": 1,
        "directions": DIRECTIONS,
        "default_status": "accepted",
        "include_pending": True,
        "accepted": accepted,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {OUT}")
    print(f"accepted_assets={len(accepted)}")


if __name__ == "__main__":
    main()
