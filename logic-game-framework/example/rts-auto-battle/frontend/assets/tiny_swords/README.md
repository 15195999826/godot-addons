# Tiny Swords Assets

RTS 示例使用的整理版美术资产目录。来源为 `D:\tmp\Tiny Swords RPG` 当前解压内容。默认单位使用 `Update 010/Factions` 的 sheet；`Free Pack/Units/Lancer` 作为例外录入，因为枪兵只有该来源提供多方向动画。

## Top-Level Categories

- `decor/`：纯装饰资源，不直接承载 gameplay 语义。
- `terrain/`：地图底层和地形覆盖资源；当前只整理资源，不接 tilemap 规则。
- `ui/`：按钮、图标、面板、banner、cursor 等界面资源。
- `units/`：可作为单位表现的 sheet，按阵营、兵种、颜色组织。
- `effects/`：爆炸、火、投射物、环境短动画。
- `scene_objects/`：场景内可放置对象，包括建筑、资源点、可交互装置。

## Subdirectories

### `decor/`

- `grassland_set/`：Update 010 的编号装饰小物。
- `vegetation/bushes/`：草丛。
- `rocks/ground/`：陆地石头。
- `rocks/water/`：水中石头。
- `sky/clouds/`：云。
- `water_props/`：水面小物。

### `terrain/`

- `ground/overlays/`：地面覆盖，如阴影。
- `water/base/`：水面底图。
- `water/foam/`：水边泡沫。
- `water/rocks/`：水域岩石。
- `bridge/`：桥。

### `ui/`

- `controls/buttons/`：按钮。
- `controls/bars/`：条形控件。
- `icons/`：图标；状态由文件名表达。
- `input/cursors/`：鼠标和指针。
- `frames/{banners,ribbons}/`：banner、ribbon、九宫格/三段式框。
- `panels/{papers,wood_table}/`：纸张、木桌等面板素材。
- `avatars/`：头像。
- `decorative/swords/`：UI 装饰剑。

### `units/`

- `knights/{pawn,warrior,archer}/`：骑士阵营完整单位 sheet；颜色由文件名表达。
- `knights/lancer/`：Free Pack 枪兵 strip；颜色、方向和动作由文件名表达。
- `knights/archer_parts/{body_no_arms,bow_overlay}/`：弓手拆件；颜色由文件名表达。
- `knights/dead/`：死亡/尸体帧。
- `goblins/torch/`：Goblin torch 单位 sheet；颜色由文件名表达。

### `effects/`

- `combat/explosion/`：爆炸。
- `environment/{dust,fire,water_splash}/`：环境效果。
- `projectiles/{arrow,dynamite}/`：投射物。

### `scene_objects/`

- `buildings/knights/<building>/`：Update 010 Knights 建筑；颜色和状态由文件名表达。
- `buildings/goblins/<building>/`：Update 010 Goblins 建筑；颜色和状态由文件名表达。
- `buildings/legacy_free_pack/<building>/`：Free Pack 旧建筑，保留用于静态场景拼装；颜色由文件名表达。
- `resources/gold/{mine,ore_stones,pickup}/`：金矿、金矿石和金币资源；状态由文件名表达。
- `resources/wood/{trees,stumps,pickup}/`：木材资源。
- `resources/food/meat/`：肉资源；`pickup/` 下是 Update 010 的肉资源生成/拾取动画。
- `resources/food/sheep/`：羊资源；Free Pack 的 `Sheep_*` 和 Update 010 的 `HappySheep_*` 都放在这里，accepted catalog 拆成 `resource/sheep_free_pack` 和 `resource/happy_sheep`。
- `resources/tools/`：工具资源。
- `devices/{barrel,tnt}/`：爆炸桶、TNT 这类场景装置；颜色由文件名表达。

## Preview

动画浏览器场景：

`res://addons/logic-game-framework/example/rts-auto-battle/frontend/asset_browser/rts_tiny_swords_animation_browser.tscn`

浏览器会读取两层数据：

- `frame_manifest.json`：自动扫描层，记录所有可切帧资源；未录用的条目在浏览器里归入 `Pending`。
- `animation_library.json`：人工录用层，按 `resource/building/unit` 组织第一版可用动画；单帧图片也按一帧动画处理。

浏览器默认展示 `Accepted`。切到 `Pending` 可以继续检查待合入资源。`ui/` 只整理入库，不进入动画预览。Directional unit 会显示 8 个方向按钮，右侧 sequence 列表只显示当前方向下的动作状态，例如 `idle` / `run` / `attack`。

`tools/generate_frame_manifest.py` 可生成 `frame_manifest.json`，记录每个多帧资产的网格、有效帧数、每帧 alpha bbox、visual-center offset 和 bottom-center offset。脚本优先使用人工确认的 override 规则；未覆盖资源会用兜底规则标记为 `confidence: "guessed"` 和 `needs_review: true`，方便后续人工复核。

`tools/generate_animation_library.py` 可生成 `animation_library.json`。第一版录用范围：

- 资源：金矿、树木、羊，以及它们产出的 gold/wood/meat pickup。
- 建筑：Update 010 的 Knights/Goblins 建筑；`wood_tower` 的彩色状态按 4 帧动画录用。
- 单位：Pawn、Warrior、Lancer、Archer，并共享 `knights/dead/Dead.png`。
- 单位方向：统一暴露 8 个方向。原始资源缺方向时会在 sequence metadata 里标记 `direction_mode`，例如 `fallback_horizontal_flip`、`shared_idle_run` 或 `partial_directional_mirror`。
- 单位动作：Lancer 不录用 `Defense` strip；Warrior 的同方向双攻击录用为 `attack_1` / `attack_2`；Pawn 只有单方向 sheet，西向方向使用 horizontal flip。
