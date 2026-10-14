class_name PostPresenter
extends RefCounted

## Fills the post office for today. Its fixtures — Pelly / Phyllis, the counter hull, the
## e-Terminal, the clock and the two window beams (`aPG_actor_ct`, `POST_OFFICE_actor_data`,
## `ef_room_sunshine_posthouse`) — are authored in `post_office.tscn`; what changes is how
## many letter piles sit on the shelf: one per stored piece of mail, up to five
## (`bPTI_actor_draw`).


func present(root: Node3D, _interior: IndoorSession) -> void:
	var piles: Node = root.get_node_or_null("MailPiles") if root != null else null
	if piles == null or Game == null or Game.post == null:
		return
	var shown: int = Game.post.get_keep_mail_sum()
	for i: int in piles.get_child_count():
		(piles.get_child(i) as Node3D).visible = i < shown
