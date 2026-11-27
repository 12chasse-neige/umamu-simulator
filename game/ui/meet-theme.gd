extends RefCounted

const INK := Color("#231e3a")
const PANEL := Color("#fffdfc")
const EDGE := Color("#dfd5eb")
const TEXT := Color("#312443")
const MUTED := Color("#625572")
const ACCENT := Color("#6840a9")
const LAVENDER := Color("#f3eaff")
const MINT := Color("#dff1e8")
const GOLD := Color("#efbf63")
const WHITE := Color("#fffdfc")
const SCRIM := Color(0.12, 0.085, 0.22, 0.67)

static var _theme: Theme
static var _heading: SystemFont


static func make() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "Inter", "Arial", "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
	_heading = font.duplicate() as SystemFont
	_heading.font_weight = 700
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", TEXT)
	_button_styles(theme, "Button", WHITE, TEXT)
	theme.set_type_variation("PrimaryButton", "Button")
	_button_styles(theme, "PrimaryButton", ACCENT, WHITE)
	theme.set_stylebox("normal", "LineEdit", box(Color("#faf7ff"), EDGE, 10))
	theme.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, ACCENT, 10))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", INK)
	theme.set_stylebox("panel", "ItemList", box(Color("#faf7ff"), EDGE, 10))
	theme.set_stylebox("selected", "ItemList", box(MINT, Color("#8bbfa5"), 3))
	theme.set_stylebox("selected_focus", "ItemList", box(MINT, ACCENT, 3))
	theme.set_stylebox("hovered", "ItemList", box(LAVENDER, EDGE, 3))
	theme.set_stylebox("hovered_selected", "ItemList", box(MINT, ACCENT, 3))
	theme.set_stylebox("hovered_selected_focus", "ItemList", box(MINT, ACCENT, 3))
	theme.set_stylebox("focus", "ItemList", box(Color.TRANSPARENT, ACCENT, 0))
	theme.set_constant("h_separation", "ItemList", 5)
	theme.set_constant("v_separation", "ItemList", 7)
	_theme = theme
	return theme


static func _button_styles(theme: Theme, type: String, fill: Color, text_color: Color) -> void:
	var dark := type == "PrimaryButton"
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, type, text_color)
	theme.set_color("font_disabled_color", type, MUTED)
	theme.set_stylebox("normal", type, box(fill, ACCENT if dark else EDGE, 10))
	theme.set_stylebox("hover", type, box(Color("#8054bd") if dark else LAVENDER, ACCENT, 10))
	theme.set_stylebox("pressed", type, box(Color("#572f97") if dark else MINT, ACCENT, 10))
	theme.set_stylebox("disabled", type, box(Color("#ebe6f1"), EDGE, 10))
	theme.set_stylebox("focus", type, box(Color.TRANSPARENT, Color("#ae81d9"), 10))


static func box(fill: Color, border: Color, padding: int, corners := 9) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(corners)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


static func panel(content: Control, width := 0.0, padding := 20) -> PanelContainer:
	var shell := PanelContainer.new()
	shell.custom_minimum_size.x = width
	var skin := box(PANEL, EDGE, padding, 14)
	skin.border_width_top = 4
	skin.shadow_color = Color(0.13, 0.08, 0.23, 0.30)
	skin.shadow_size = 10
	skin.shadow_offset = Vector2(0, 5)
	shell.add_theme_stylebox_override("panel", skin)
	shell.add_child(content)
	return shell


static func scrim(opacity := 0.67) -> ColorRect:
	var shade := ColorRect.new()
	shade.color = Color(SCRIM, opacity)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shade


static func label(value: String, size_value: int, color := TEXT) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_font_size_override("font_size", size_value)
	text.add_theme_color_override("font_color", color)
	if size_value >= 23:
		make()
		text.add_theme_font_override("font", _heading)
	return text


static func column(spacing: int) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", spacing)
	return container


static func row(spacing: int) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", spacing)
	return container


static func button(title: String, action: Callable, primary := false) -> Button:
	var control := Button.new()
	control.text = title
	if primary:
		control.theme_type_variation = &"PrimaryButton"
	control.pressed.connect(action)
	return control
