class_name TownUpkeep
extends RefCounted

## What the town does as the calendar turns: the midnight date change, the 06:00 field
## renewal, and the community board. `Game` wires the `Clock` signals to these.


## `mTM_*` time step: `Kabu_manager` runs when the date changes (midnight, not 06:00).
## `mTM_renewal_renew_time` raises the weather and daily flags on a change of calendar date,
## at midnight, not at the 06:00 field renewal, which is growth, weeds and the lost and found.
static func on_day_changed() -> void:
	Game.shops.stalk_market.update(Clock.year, Clock.month, Clock.day)
	## `mEv_RenewalDataEveryDay`: the Academy sign-up comes due the day after the job.
	Game.hra.renew_day()
	## One roll for the new date (`mEnv_DecideWeather` / `aWeather_ChangeWeatherTime0`).
	var previous_weather: StringName = Game.town.weather
	Game.apply_weather_roll(Weather.roll())
	Game.apply_event_weather()
	## Fine after rain or snow: a rainbow over the falls today and gyroids in the ground with
	## the next growth (`mEnv_PreRainNowFine_Init`).
	Game.rainbow.note_weather_change(previous_weather, Game.town.weather, Clock.month, Clock.day)
	if Rainbow.pre_rain_now_fine(previous_weather, Game.town.weather):
		Game.town.gyroids_scheduled = true


## The 06:00 renewal, `days` calendar days after the last one.
static func on_field_renewed(days: int) -> void:
	var town: TownState = Game.town
	Game.shops.renew(days)
	town.weed_days_pending += maxi(days, 0)
	town.melt_snowmen(days)
	## `mAGrw_ClearSpoiledKabu` / `mAGrw_SpoilKabu` / `mAGrw_SpoilAllPossession`.
	FieldItems.renew(
		FieldItems.sunday_passed(Clock.year, Clock.month, Clock.day, days),
		Game.inventory, Game.get_tree()
	)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	MailDelivery.send_valentines(rng)
	MailDelivery.send_birthday_cards(rng)
	MailDelivery.send_mother_mail(rng)
	CalendarBook.note_today()
	HouseCockroaches.save_play_time(Game.interiors.player_house())
	Game.refresh_shop_set()
	Game.police.renew(Game.in_police_box())
	Game.refresh_police_set()
	MailDelivery.deliver_farway_mail()
	MailDelivery.deliver_nook_mail()
	Game.redd.check_unlock()
	update_notice_board()


## `mNtc_set_auto_nwrite_data`: seasonal notices whose day has come, and the fishing-contest
## results and mail that follow.
static func update_notice_board() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var names: Array = _resident_names()
	var town: TownState = Game.town
	var written: int = Game.notice_board.auto_write(
		Clock.year, Clock.month, Clock.day, Clock.hour,
		NoticeBoard.common_free(town.town_name, Game.shops.nook_level()),
		func(ordinal: int) -> Dictionary: return FishRecord.holder(town.fish_records, ordinal, names, rng)
	)
	## `mFR_fishmail`: right after the board.
	var sent: int = FishRecord.send_mail(
		town.fish_records, EventDates.ordinal(Clock.year, Clock.month, Clock.day), Clock.hour,
		names, Game.catalog.owned_ids(), Game.resident.player_name, rng,
		MailDelivery.to_mailbox_or_post
	)
	if sent > 0:
		Game.post_notice(MailDelivery.NEW_MAIL_NOTICE)
	## `mNtc_check_treasure` when nothing seasonal went up.
	Game.treasure_due = written == 0
	try_treasure(World.find(Game.get_tree()) if Game.get_tree() != null else null)


## A villager may bury treasure once the field is up (`BuriedTreasure`).
static func try_treasure(world: Node) -> void:
	if not Game.treasure_due or world == null or world.get("grid") == null:
		return
	Game.treasure_due = false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	BuriedTreasure.check(world, rng)


## `mEvMN_GetJointEventRandomNpc`: the residents who could be out fishing.
static func _resident_names() -> Array:
	var names: Array = []
	for id: StringName in Game.residents.resident_ids():
		var villager: VillagerData = VillagerCatalog.get_villager(id)
		if villager != null:
			names.append(villager.display_name)
	return names
