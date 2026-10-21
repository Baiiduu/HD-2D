extends AcceptDialog
## Packaged text remains available without a browser or network connection.

const POLICY_PATH := "res://data/legal/privacy_policy.txt"
const POLICY_URL := "https://huitan-privacy.jessegames.chatgpt.site/"

func _ready() -> void:
	title = "回弹隐私政策"
	ok_button_text = "关闭"
	exclusive = true
	unresizable = false
	var dialog_theme := Theme.new()
	dialog_theme.default_font = preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")
	dialog_theme.default_font_size = 20
	theme = dialog_theme
	var body := RichTextLabel.new()
	body.name = "PolicyText"
	body.text = FileAccess.get_file_as_string(POLICY_PATH)
	body.custom_minimum_size = Vector2(600, 360)
	body.scroll_active = true
	body.selection_enabled = true
	add_child(body)
	var web := add_button("浏览器查看", false, "web")
	web.tooltip_text = POLICY_URL
	custom_action.connect(func(action: StringName):
		if action == &"web": OS.shell_open(POLICY_URL))
