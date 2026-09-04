class_name TestNpcFace
extends GdUnitTestSuite

## `aNPC_tex_anm_ctrl`: eyes blink on their own, the mouth only moves while the message
## window is laying text in.

const FRAME := 1.0 / 30.0


func _run(face: NpcFaceAnim, frames: int, uttering: bool) -> Dictionary:
	var eye_counts: Dictionary = {}
	var mouth_counts: Dictionary = {}
	for _i: int in frames:
		face.tick(FRAME, uttering)
		eye_counts[face.eye_pattern] = int(eye_counts.get(face.eye_pattern, 0)) + 1
		mouth_counts[face.mouth_pattern] = int(mouth_counts.get(face.mouth_pattern, 0)) + 1
	return {"eye": eye_counts, "mouth": mouth_counts}


func test_mouth_stays_shut_until_the_window_utters() -> void:
	var face := NpcFaceAnim.new()
	var counts: Dictionary = _run(face, 300, false)
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_SHUT)
	assert_int(counts["mouth"].size()).is_equal(1)


func test_mouth_flaps_while_uttering_then_closes() -> void:
	var face := NpcFaceAnim.new()
	var counts: Dictionary = _run(face, 300, true)
	## typeB never reaches a full open, so a flap is any non-shut pattern.
	var moved: bool = (
		counts["mouth"].has(NpcFaceAnim.MOUTH_SMALL)
		or counts["mouth"].has(NpcFaceAnim.MOUTH_OPEN)
	)
	assert_bool(moved).is_true()
	assert_bool(counts["mouth"].has(NpcFaceAnim.MOUTH_SHUT)).is_true()
	_run(face, 10, false)
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_SHUT)


func test_eyes_blink_but_stay_mostly_open() -> void:
	var face := NpcFaceAnim.new()
	var frames := 1800
	var counts: Dictionary = _run(face, frames, false)
	assert_bool(counts["eye"].has(NpcFaceAnim.EYE_SHUT)).is_true()
	assert_bool(counts["eye"].has(NpcFaceAnim.EYE_HALF)).is_true()
	## `32 + RANDOM(16)` counter units at 0.5 per frame is a 64–94 frame hold between
	## bursts, so the eyes are open for the large majority of a minute.
	var open: int = int(counts["eye"].get(NpcFaceAnim.EYE_OPEN, 0))
	assert_bool(float(open) / float(frames) > 0.7).is_true()


func test_eyes_never_stick_shut() -> void:
	var face := NpcFaceAnim.new()
	var shut_run := 0
	var worst := 0
	for _i: int in 1800:
		face.tick(FRAME, false)
		if face.eye_pattern == NpcFaceAnim.EYE_SHUT:
			shut_run += 1
			worst = maxi(worst, shut_run)
		else:
			shut_run = 0
	## `{EYE_SHUT, 3}` at 0.5 per frame is six frames plus the step that ends it.
	assert_bool(worst <= 8).is_true()


func test_long_frame_hitch_does_not_replay_the_whole_gap() -> void:
	var face := NpcFaceAnim.new()
	face.tick(5.0, false)
	assert_bool(face.eye_pattern >= 0).is_true()
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_SHUT)


func test_mood_maps_onto_wait_pose_emotes() -> void:
	assert_int(NpcFaceAnim.emote_from_mood(VillagerState.Mood.NORMAL)).is_equal(
		NpcFaceAnim.Emote.NORMAL
	)
	assert_int(NpcFaceAnim.emote_from_mood(VillagerState.Mood.HAPPY)).is_equal(
		NpcFaceAnim.Emote.LAUGH
	)
	assert_int(NpcFaceAnim.emote_from_mood(VillagerState.Mood.ANGRY)).is_equal(
		NpcFaceAnim.Emote.ANGRY
	)
	assert_int(NpcFaceAnim.emote_from_mood(VillagerState.Mood.SAD)).is_equal(
		NpcFaceAnim.Emote.SAD
	)
	assert_int(NpcFaceAnim.emote_from_mood(VillagerState.Mood.SLEEPY)).is_equal(
		NpcFaceAnim.Emote.SLEEPY
	)


func test_emotion_holds_use_authored_eye_frames() -> void:
	var face := NpcFaceAnim.new()
	face.set_emote(NpcFaceAnim.Emote.ANGRY)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_ANGRY)
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_ANGRY_SHUT)
	_run(face, 120, false)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_ANGRY)

	face.set_emote(NpcFaceAnim.Emote.SAD)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_SAD)

	face.set_emote(NpcFaceAnim.Emote.LAUGH)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_LAUGH)

	face.set_emote(NpcFaceAnim.Emote.SURPRISE)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_SURPRISE)

	face.set_emote(NpcFaceAnim.Emote.CRY)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_CRY)

	face.set_emote(NpcFaceAnim.Emote.SLEEPY)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_SHUT)


func test_angry_mouth_flaps_on_emotion_bank_while_uttering() -> void:
	var face := NpcFaceAnim.new()
	face.set_emote(NpcFaceAnim.Emote.ANGRY)
	var counts: Dictionary = _run(face, 300, true)
	var moved: bool = (
		counts["mouth"].has(NpcFaceAnim.MOUTH_ANGRY_SMALL)
		or counts["mouth"].has(NpcFaceAnim.MOUTH_ANGRY_OPEN)
		or counts["mouth"].has(NpcFaceAnim.MOUTH_ANGRY_SHUT)
	)
	assert_bool(moved).is_true()
	_run(face, 10, false)
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_ANGRY_SHUT)


func test_frame_paths_follow_the_faces_pipeline_layout() -> void:
	assert_str(NpcFace.frame_path(&"xct", "eye", 0)).is_equal(
		"res://assets/generated/characters/faces/xct_eye0.png"
	)
	assert_str(NpcFace.frame_path(&"xct", "mouth", 5)).is_equal(
		"res://assets/generated/characters/faces/xct_mouth5.png"
	)


func test_bind_fails_without_face_quads_on_host() -> void:
	## No 32×16 eye/mouth quads on an empty node.
	var face := NpcFace.new()
	var host := Node3D.new()
	add_child(host)
	assert_bool(face.bind(host, &"xct")).is_false()
	face.tick(FRAME, true)
	host.queue_free()


func test_mirror_expand_duplicates_half_face_for_gx_mirror() -> void:
	var src := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	src.fill(Color(0, 0, 0, 0))
	src.set_pixel(4, 8, Color(1, 0, 0, 1))
	var out := NpcFace._mirror_expand_image(src, 64)
	assert_int(out.get_width()).is_equal(64)
	assert_that(out.get_pixel(4, 8)).is_equal(Color(1, 0, 0, 1))
	assert_that(out.get_pixel(59, 8)).is_equal(Color(1, 0, 0, 1))


func test_achd_mirrored_target_gets_gx_mirror_not_a_stretch() -> void:
	## Rover's baked eye quad is 512×128 (8× of 64×16). Swapping must mirror the
	## 32×16 half first — a plain resize left only the left eye stretched.
	var face := NpcFace.new()
	var half := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	half.fill(Color(0, 0, 0, 0))
	half.set_pixel(2, 4, Color(0, 1, 0, 1))
	var tex := ImageTexture.create_from_image(half)
	var out: Texture2D = face._mirror_expand_to(tex, Vector2i(512, 128))
	var img: Image = out.get_image()
	assert_int(img.get_width()).is_equal(512)
	assert_int(img.get_height()).is_equal(128)
	## Pixel (2,4) scales ×8 → (16,32); mirror of that in 64-space is x=61 → (488,32).
	assert_that(img.get_pixel(16, 32)).is_equal(Color(0, 1, 0, 1))
	assert_that(img.get_pixel(488, 32)).is_equal(Color(0, 1, 0, 1))


func test_face_quad_accepts_achd_upscaled_eye_sizes() -> void:
	## Native CI4, GX_MIRROR bake, and ACHD 8× of 32×16.
	var native := ImageTexture.create_from_image(Image.create(32, 16, false, Image.FORMAT_RGBA8))
	var mirrored := ImageTexture.create_from_image(Image.create(64, 16, false, Image.FORMAT_RGBA8))
	var achd := ImageTexture.create_from_image(Image.create(256, 128, false, Image.FORMAT_RGBA8))
	var body := ImageTexture.create_from_image(Image.create(128, 128, false, Image.FORMAT_RGBA8))
	assert_bool(NpcFace._is_face_quad(native)).is_true()
	assert_bool(NpcFace._is_face_quad(mirrored)).is_true()
	assert_bool(NpcFace._is_face_quad(achd)).is_true()
	assert_bool(NpcFace._is_face_quad(body)).is_false()


func test_manpu_smile_parks_mouth_open() -> void:
	assert_int(NpcManpu.mouth_hold_for("smile1")).is_equal(NpcFaceAnim.MOUTH_OPEN)
	assert_int(NpcManpu.mouth_hold_for("gaaan1")).is_equal(NpcFaceAnim.MOUTH_ANGRY_OPEN)
	assert_int(NpcManpu.mouth_hold_for("ha_d1")).is_equal(NpcFaceAnim.MOUTH_ANGRY_SMALL)
	assert_int(NpcManpu.mouth_hold_for("niko_d1")).is_equal(NpcFaceAnim.MOUTH_SHUT)
	assert_int(NpcManpu.mouth_hold_for("hate1")).is_equal(NpcFaceAnim.MOUTH_ANGRY_SHUT)
	assert_int(NpcManpu.mouth_hold_for("reset")).is_equal(NpcFaceAnim.MOUTH_SHUT)
	var face := NpcFaceAnim.new()
	face.set_emote(NpcFaceAnim.Emote.LAUGH, NpcFaceAnim.MOUTH_OPEN)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_LAUGH)
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_OPEN)
	face.set_emote(NpcFaceAnim.Emote.SURPRISE, NpcFaceAnim.MOUTH_ANGRY_OPEN)
	assert_int(face.eye_pattern).is_equal(NpcFaceAnim.EYE_SURPRISE)
	assert_int(face.mouth_pattern).is_equal(NpcFaceAnim.MOUTH_ANGRY_OPEN)
