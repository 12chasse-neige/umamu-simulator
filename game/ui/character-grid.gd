extends ItemList

const Portraits := preload("res://game/ui/character-portraits.gd")

func configure(columns: int, cell_width: int, portrait_width: int, height: int) -> void:
	max_columns = columns
	same_column_width = true
	fixed_column_width = cell_width
	fixed_icon_size = Vector2i(portrait_width, roundi(portrait_width * 1.10))
	icon_mode = ItemList.ICON_MODE_TOP
	max_text_lines = 2
	custom_minimum_size.y = height
	add_theme_font_size_override("font_size", 14)


func add_profile(title: String, model: String) -> int:
	var index := add_item(title, Portraits.for_node(self, model))
	set_item_tooltip(index, title)
	return index
