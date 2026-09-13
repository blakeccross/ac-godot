shader_type canvas_item;

// `mIV_set_base_frame_dl` (`m_inventory_ovl.c`) draws the pockets window's paper
// fill through a 32x32 render-tile window that slides across the background
// texture every frame. The slide itself is the shared full-screen-menu scroll
// from `m_submenu_ovl.c` (`control->texture_pos[0/1] += 0.3535`, wrapped at
// 1024, ~60Hz) reused by every `mSM_*_ovl` screen (bank, catalog, mail, music,
// needlework, ...), not something bespoke to inventory.
//
// `window_shell.png` bakes the paper (`paper.png` = decomp `backgound_texture`
// / ITM_CLOTH226, the default menu wallpaper) into the shell at a fixed
// screen-space tiling. This shader re-samples `paper.png` at that same tiling
// but offsets it over time, so the fill visibly scrolls like the original
// while the baked alpha (silhouette + border AA) stays exactly as authored.

uniform sampler2D paper_tex: source_color, filter_linear, repeat_enable;
// `window_shell.png` bakes paper at a 128px period (paper.png's own 256px tile
// halved by the pipeline's 2x supersample downscale) -> 2 paper.png texels per
// shell pixel.
uniform float paper_px_per_shell_px = 2.0;
// 0.3535 texel/frame @ 60Hz (`m_submenu_ovl.c`) = ~21.21 texel/sec, applied in
// paper.png's own pixel space.
uniform vec2 scroll_texels_per_sec = vec2(21.21, 21.21);

void fragment() {
	vec4 shell = texture(TEXTURE, UV);
	vec2 shell_px = UV / TEXTURE_PIXEL_SIZE;
	vec2 paper_size = vec2(textureSize(paper_tex, 0));
	vec2 paper_px = shell_px * paper_px_per_shell_px + scroll_texels_per_sec * TIME;
	vec2 paper_uv = fract(paper_px / paper_size);
	vec4 paper = texture(paper_tex, paper_uv);
	COLOR = vec4(paper.rgb, shell.a);
}
