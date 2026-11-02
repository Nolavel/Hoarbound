class_name GameplayUI
extends Node

## Binds screen-space presentation to the authoritative player before entering
## the tree. The player scene can be spawned and simulated without a HUD.

func bind_player(player: Player) -> void:
	if player == null:
		push_error("GameplayUI requires a Player to bind.")
		return
	var cursor := get_node(^"GameplayCanvas/MouseCursorUI") as MouseCursorUI
	cursor.player = player
	var marker := get_node(^"GameplayCanvas/PickupMarkerUI") as PickupMarkerUI
	marker.interact_component = player.get_node_or_null(^"InteractComponent") as InteractComponent
	var vitals := get_node(^"VitalHUD") as CanvasLayer
	var health_strip := vitals.get_node(^"HealthStrip") as HealthStrip
	health_strip.health = player.get_node_or_null(^"PlayerHealthSystem") as PlayerHealthSystem
	var cluster := vitals.get_node(^"VitalCluster") as VitalCluster
	cluster.bio_monitor = player.get_node_or_null(^"BioMonitorManager") as BioMonitorManager
	var quick := get_node(^"GameplayCanvas/QuickAccess") as QuickAccessUI
	quick.quick_access_component = player.get_node_or_null(^"QuickAccessComponent") as QuickAccessComponent
	var anchors := player.get_node_or_null(^"HenryUALVisual/QuickAccessAnchors")
	if anchors == null:
		push_error("GameplayUI: Henry is missing QuickAccessAnchors.")
		return
	quick.coat_left_anchor = anchors.get_node_or_null(^"CoatLeftAnchor") as Node3D
	quick.coat_right_anchor = anchors.get_node_or_null(^"CoatRightAnchor") as Node3D
	quick.thigh_left_anchor = anchors.get_node_or_null(^"ThighLeftAnchor") as Node3D
	quick.pack_lid_anchor = anchors.get_node_or_null(^"PackLidAnchor") as Node3D
	quick.hands_anchor = anchors.get_node_or_null(^"HandsAnchor") as Node3D
	var feedback := get_node(^"FeedbackUI") as PlayerFeedbackUI
	var held := player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	var wood := player.get_node_or_null(^"WoodWorkComponent") as WoodWorkComponent
	var rest := player.get_node_or_null(^"RestComponent") as RestComponent
	var consumption := player.get_node_or_null(^"ConsumptionController") as ConsumptionController
	if quick.quick_access_component != null:
		quick.quick_access_component.readout_changed.connect(feedback.show_quick)
	if held != null:
		held.hint_changed.connect(feedback.show_held)
	if wood != null:
		wood.hint_changed.connect(feedback.show_wood)
	if rest != null:
		rest.status_requested.connect(feedback.show_rest)
	if consumption != null:
		consumption.water_status_requested.connect(feedback.show_water)
	var hub := player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	var panel := get_node(^"PlayerHubPanel") as PlayerHubPanel
	if hub != null:
		panel.hub = hub
		panel.visible = false
		hub.bind_panel(panel)
