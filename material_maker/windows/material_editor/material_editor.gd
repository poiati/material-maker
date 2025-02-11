extends "res://material_maker/windows/node_editor/node_editor.gd"


onready var preview_editor : TextEdit = $Sizer/Tabs/Preview
var exports : Dictionary = {}


func _ready():
	preview_editor.add_color_region("//", "", Color(0, 0.5, 0), true)


func set_model_data(data) -> void:
	.set_model_data(data)
	if data.has("preview_shader"):
		preview_editor.text = data.preview_shader
		preview_editor.clear_undo_history()
	if data.has("exports"):
		exports = data.exports

func get_model_data() -> Dictionary:
	var data = .get_model_data()
	data.preview_shader = preview_editor.text
	data.exports = exports
	return data
