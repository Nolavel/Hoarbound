extends SceneTree

## Guards the deliberately minimal hand-off from the engine boot screen to the
## First Exit scene.
## Run: godot --headless --script tests/systems/test_startup_presentation.gd

const CARD_PATH: String = "res://scenes/splash/splash_scene.tscn"
const MAIN_PATH: String = "res://scenes/world/key_west/key_west_reality.tscn"
const LEGACY_SPLASH_PATH: String = "res://assets/textures/ui/splash/Splash_testing.png"
const PREMIUM_BLACK := Color(0.0627451, 0.0627451, 0.0627451, 1.0)

var _failures: int = 0


func _initialize() -> void:
	_test_engine_boot_is_plain_black()
	_test_title_card_content()
	_test_island_owns_the_title_card()

	if _failures > 0:
		push_error("startup presentation: %d check(s) failed" % _failures)
		quit(1)
		return
	print("startup presentation: black boot and Hoarbound ALPHA 0.1 title card passed")
	quit(0)


func _test_engine_boot_is_plain_black() -> void:
	_check(
		not bool(ProjectSettings.get_setting("application/boot_splash/show_image", true)),
		"the engine boot still shows an image"
	)
	var boot_color: Color = ProjectSettings.get_setting(
		"application/boot_splash/bg_color",
		Color.BLACK
	)
	_check(boot_color.is_equal_approx(PREMIUM_BLACK), "boot black is not #101010")
	_check(
		String(ProjectSettings.get_setting("application/boot_splash/image", "")).is_empty(),
		"a boot splash image is still configured"
	)
	_check(not FileAccess.file_exists(LEGACY_SPLASH_PATH), "the legacy splash asset still exists")


func _test_title_card_content() -> void:
	var packed := load(CARD_PATH) as PackedScene
	_check(packed != null, "the startup title scene does not load")
	if packed == null:
		return
	var card := packed.instantiate()
	_check(card is StartupTitleCard, "the startup scene is not a StartupTitleCard")

	var background := card.get_node_or_null(^"Cover/Background") as ColorRect
	var title := card.get_node_or_null(^"Cover/Center/Titles/Title") as Label
	var version := card.get_node_or_null(^"Cover/Center/Titles/Version") as Label
	_check(background != null, "the title card has no background")
	_check(title != null, "the title card has no title")
	_check(version != null, "the title card has no version label")
	if background != null:
		_check(background.color.is_equal_approx(PREMIUM_BLACK), "card black is not #101010")
	if title != null:
		_check(title.text == "Hoarbound", "the public game title changed")
	if version != null:
		_check(version.text == "ALPHA 0.1", "the build is not labelled ALPHA 0.1")
	card.free()


func _test_island_owns_the_title_card() -> void:
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene", "")) == MAIN_PATH,
		"the project no longer launches the playable island"
	)
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	_check(source.contains(CARD_PATH), "the main island does not instance the startup card")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("startup presentation: %s" % message)
