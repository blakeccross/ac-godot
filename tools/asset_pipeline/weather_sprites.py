"""Snow flakes and cherry petals (`ac_weather_snow` / `ac_weather_sakura`) as sprites, and
the two-texture effects whose converted GLB keeps only one tile: the waterfall rainbow
(`obj_fallS_rainbowT_model`: RGBA16 colour bands in tile 0, the I4 fade mask in tile 1)
and the Harvest Moon's pond reflection (`ef_moon01_01_modelT`: I4 moon disc in tile 0,
the I4 ripple the evw anime scrolls in tile 1). Also the station statue's eyes and mouths
(`ac_douzou`: `eye_tbl` / `mouth_tbl` bound on segments 8 / 9 of the face / mouth lists),
saved under `assets/generated/environment/douzou/` by symbol.

Each is one small card whose colour and texture come from its `*_setmode` list, so the
display-list walker rasterises setmode + model flat (the card lies in the model's XY
plane) into `assets/generated/effects/{ef_yuki01,ef_hanabira01}_sprite.png`. The
runtime draws them on billboards / tumbling quads sized to the model's extent.

Both combiners take SHADE; the cards are lit (`_texture_z_light_fog_prim_xlu`), so
the bake uses full white shade rather than the vertex normals the walker would read
as colours.
"""

from __future__ import annotations

from typing import Any

from .achd import load_achd_pack
from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .mapfile import parse_map
from .rel import RelData
from .texbank import image_png_bytes
from .ui_gbi import Op, TextureCache, Tile, UiWalker, rasterize
from PIL import Image

## name -> (ops, model bounds (left, top, width, height) in model units)
SPRITES: dict[str, tuple[list[Op], tuple[float, float, float, float]]] = {
	"ef_yuki01_sprite": ([Op("ef_yuki01_setmode"), Op("ef_yuki01_00_model")], (-1000.0, 1000.0, 2000.0, 2000.0)),
	"ef_hanabira01_sprite": (
		[Op("ef_hanabira01_00_setmode"), Op("ef_hanabira01_00_modelT")], (-100.0, 100.0, 200.0, 200.0)),
}
SPRITE_PX = 64
## (model, tile, png name): tiles saved as bound, for runtime shaders.
TILE_EXPORTS: list[tuple[str, int, str]] = [
	("obj_fallS_rainbowT_model", 0, "obj_fall_rainbow_color"),
	("obj_fallS_rainbowT_model", 1, "obj_fall_rainbow_mask"),
	("ef_moon01_01_modelT", 0, "ef_moon01_disc"),
	("ef_moon01_01_modelT", 1, "ef_moon01_ripple"),
]

## (model, segment, symbols): per-player textures `ac_douzou` binds before drawing a model.
DOUZOU_DIR = "environment/douzou"
DOUZOU_FACE_EXPORTS: list[tuple[str, int, list[str]]] = [
	(f"obj_{season}_douzou_boy_face_model", 8,
		[f"obj_{season}_douzou_{sex}{n}_tex_pic_i4" for sex in "bg" for n in range(1, 9)])
	for season in "sw"
] + [
	(f"obj_{season}_douzou_boy_mouth_model", 9,
		[f"obj_{season}_douzou_{m}_tex_pic_i4" for m in ("bm1", "bm2", "gm1", "gm2")])
	for season in "sw"
]


def _save_tile(textures: TextureCache, walker: UiWalker, tile_no: int, path, project_root) -> bool:
	tile: Tile | None = walker.tiles.get(tile_no)
	if tile is None:
		return False
	arr = textures.get(tile)
	image = Image.fromarray((arr * 255 + 0.5).clip(0, 255).astype("uint8"), "RGBA")
	path.write_bytes(image_png_bytes(image))
	write_import_sidecar(path, project_root)
	return True


def export_weather_sprites(cfg: PipelineConfig) -> dict[str, Any]:
	try:
		rel = RelData(cfg.rel_path)
		symbols = parse_map(cfg.map_path)
	except Exception as exc:  # noqa: BLE001
		return {"ok": False, "error": f"{type(exc).__name__}: {exc}", "written": 0}
	achd = load_achd_pack(cfg.achd_root, cfg.achd_cache) if cfg.achd_enabled and cfg.achd_root else None
	textures = TextureCache(rel, achd)
	out_dir = cfg.godot_generated / "effects"
	out_dir.mkdir(parents=True, exist_ok=True)
	written = 0
	for name, (ops, bounds) in SPRITES.items():
		batches = UiWalker(rel, symbols).run(ops)
		for batch in batches:
			for tri in batch.tris:
				for v in tri:
					v.rgba = (255, 255, 255, 255)
		image = rasterize(batches, textures, bounds, SPRITE_PX / bounds[2])
		(out_dir / f"{name}.png").write_bytes(image_png_bytes(image))
		write_import_sidecar(out_dir / f"{name}.png", cfg.project_root)
		written += 1
	for model, tile_no, name in TILE_EXPORTS:
		walker = UiWalker(rel, symbols)
		walker.run([Op(model, draw=False)])
		written += _save_tile(textures, walker, tile_no, out_dir / f"{name}.png", cfg.project_root)
	douzou_dir = cfg.godot_generated / DOUZOU_DIR
	douzou_dir.mkdir(parents=True, exist_ok=True)
	for model, segment, syms in DOUZOU_FACE_EXPORTS:
		for sym in syms:
			## `eye_tbl` reuses b7 for the seventh girl face; there is no g7.
			if not any(s.name == sym for s in symbols):
				continue
			walker = UiWalker(rel, symbols)
			walker.run([Op(model, draw=False, segments={segment: sym})])
			written += _save_tile(textures, walker, 0, douzou_dir / f"{sym}.png", cfg.project_root)
	return {"ok": True, "written": written, "out": str(out_dir)}
