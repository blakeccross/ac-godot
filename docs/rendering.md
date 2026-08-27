# Rendering and platforms

## Renderer

- **Method:** Forward+ (`rendering/renderer/rendering_method=forward_plus`)
- **Why:** Desktop-first 3D village with day/night and several lights. Forward+ is Godot's advanced clustered renderer (Vulkan, Metal, or Direct3D 12).
- **Not targeting:** Compatibility (GL) or Mobile renderers in Phase 0. Do not rely on Compatibility-only features.

MSAA 3D is set to 2x. Do not add heavy post-processing until there is a world to look at.

## Resolution

- Window: **1280×720**, 16:9, resizable
- Stretch: `canvas_items` + aspect `expand` (UI scales; 3D uses a real camera)

The GameCube title was approximately 4:3 at ~640×480. This project is a desktop recreation, not a pixel-perfect internal-resolution match.

## Platforms

| Platform | Role |
| --- | --- |
| macOS | Primary development |
| Windows | Supported desktop target |
| Linux | Supported desktop target |
| Web, mobile, consoles | Not a Phase 0 goal |

Export presets can wait until a playable slice exists. Enabling them does not require changing the renderer.

## Placeholder art

Use Godot primitives, solid colors, and simple lights until a system is playable.

Converted disc assets (GLB/PNG) are produced by `python3 tools/build_assets.py` into `assets/generated/` and are **not committed**. Import 2D textures with nearest filtering. Do not upscale or sharpen source art. See [asset_pipeline.md](asset_pipeline.md).
