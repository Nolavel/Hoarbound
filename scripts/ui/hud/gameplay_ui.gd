class_name GameplayUI
extends Node

var _hub: PlayerHubComponent
var _interact: InteractComponent
@onready var _hub_glow: EdgeGlowOverlay = $HubFeedback/EdgeGlowOverlay
@onready var _compass_layer: CanvasLayer = $Compass


func _ready() -> void:
	_sync_hub_feedback()


func _process(_delta: float) -> void:
	_sync_hub_feedback()


## Hide the layer, not the strip: preserve the strip's own world/profile rule.
func _sync_hub_feedback() -> void:
	var open: bool = is_instance_valid(_hub) and _hub.is_open()
	var handling: PackHandling = _hub.get_pack_hands() if open else null
	var working: bool = is_instance_valid(handling) and handling.enabled
	var picking: bool = (is_instance_valid(_interact) and _interact.is_pickup_in_progress()) or (is_instance_valid(_hub) and _hub.is_stowing_pickup())
	_compass_layer.visible = not open and not picking
	if _hub_glow.visible != working:
		_hub_glow.set_hub_active(working)
	_hub_glow.set_action_active(working and (handling.is_taking() or handling.is_carrying() or (is_instance_valid(handling.cursor) and handling.cursor.hovering)))


func _on_hub_result(success: bool) -> void:
	_sync_hub_feedback()
	_hub_glow.show_result(success)

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
	_interact = marker.interact_component
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
	quick.thigh_right_anchor = anchors.get_node_or_null(^"ThighRightAnchor") as Node3D
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
		_hub = hub
		hub.hub_opened.connect(_sync_hub_feedback)
		hub.hub_closed.connect(_sync_hub_feedback)
		hub.action_result.connect(_on_hub_result)
	var load_banner := get_node(^"BackpackLoadBanner") as BackpackLoadBanner
	load_banner.bind_player(player, quick)
