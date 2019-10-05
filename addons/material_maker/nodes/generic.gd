tool
extends GraphNode
class_name MMGraphNodeGeneric

var generator = null setget set_generator

var controls = {}
var ignore_parameter_change = ""
var output_count = 0

var preview : TextureRect
var preview_index : int = -1
var preview_position : int
var preview_size : int
var preview_timer : Timer = null

func set_generator(g):
	generator = g
	generator.connect("parameter_changed", self, "on_parameter_changed")
	call_deferred("update_node")

func on_close_request():
	generator.get_parent().remove_generator(generator)

func on_offset_changed():
	generator.set_position(offset)

func on_parameter_changed(p, v):
	if ignore_parameter_change == p:
		return
	var o = controls[p]
	if o is LineEdit:
		o.text = str(v)
	elif o is SpinBox:
		o.value = v
	elif o is HSlider:
		o.value = v
	elif o is OptionButton:
		o.selected = v
	elif o is CheckBox:
		o.pressed = v
	elif o is ColorPickerButton:
		o.color = MMType.deserialize_value(v)
	elif o is MMGradientEditor:
		var gradient : MMGradient = MMGradient.new()
		gradient.deserialize(v)
		o.value = gradient
	else:
		print("unsupported widget "+str(o))
	update_shaders()

func initialize_properties():
	var parameter_names = []
	for p in generator.get_parameter_defs():
		parameter_names.push_back(p.name)
	for c in controls:
		if parameter_names.find(c) == -1:
			continue
		var o = controls[c]
		if generator.parameters.has(c):
			on_parameter_changed(c, generator.parameters[c])
		if o is LineEdit:
			o.connect("text_changed", self, "_on_text_changed", [ o.name ])
		elif o is SpinBox:
			o.connect("value_changed", self, "_on_value_changed", [ o.name ])
		elif o is HSlider:
			o.connect("value_changed", self, "_on_value_changed", [ o.name ])
		elif o is OptionButton:
			o.connect("item_selected", self, "_on_value_changed", [ o.name ])
		elif o is CheckBox:
			o.connect("toggled", self, "_on_value_changed", [ o.name ])
		elif o is ColorPickerButton:
			o.connect("color_changed", self, "_on_color_changed", [ o.name ])
		elif o is Control and o.filename == "res://addons/material_maker/widgets/gradient_editor.tscn":
			o.connect("updated", self, "_on_gradient_changed", [ o.name ])
		else:
			print("unsupported widget "+str(o))

func update_shaders():
	get_parent().send_changed_signal()
	update_preview()

func _on_text_changed(new_text, variable):
	ignore_parameter_change = variable
	generator.set_parameter(variable, float(new_text))
	ignore_parameter_change = ""
	update_shaders()

func _on_value_changed(new_value, variable):
	ignore_parameter_change = variable
	generator.set_parameter(variable, new_value)
	ignore_parameter_change = ""
	update_shaders()

func _on_color_changed(new_color, variable):
	ignore_parameter_change = variable
	generator.set_parameter(variable, new_color)
	ignore_parameter_change = ""
	update_shaders()

func _on_gradient_changed(new_gradient, variable):
	ignore_parameter_change = variable
	generator.set_parameter(variable, MMType.serialize_value(new_gradient))
	ignore_parameter_change = ""
	update_shaders()

func create_parameter_control(p : Dictionary):
	var control = null
	if p.type == "float":
		if p.has("widget") and p.widget == "spinbox":
			control = SpinBox.new()
		else:
			control = preload("res://addons/material_maker/widgets/hslider.tscn").instance()
		control.min_value = p.min
		control.max_value = p.max
		control.step = 0.005 if !p.has("step") else p.step
		control.allow_greater = true
		control.allow_lesser = true
		if p.has("default"):
			control.value = p.default
		control.rect_min_size.x = 80
	elif p.type == "size":
		control = OptionButton.new()
		for i in range(p.first, p.last+1):
			var s = pow(2, i)
			control.add_item("%dx%d" % [ s, s ])
			control.selected = 0 if !p.has("default") else p.default-p.first
	elif p.type == "enum":
		control = OptionButton.new()
		for i in range(p.values.size()):
			var value = p.values[i]
			control.add_item(value.name)
			control.selected = 0 if !p.has("default") else p.default
	elif p.type == "boolean":
		control = CheckBox.new()
	elif p.type == "color":
		control = ColorPickerButton.new()
	elif p.type == "gradient":
		control = preload("res://addons/material_maker/widgets/gradient_editor.tscn").instance()
	return control

func update_node():
	# Clean node
	var custom_node_buttons = null
	remove_child(preview)
	if preview_timer != null:
		preview_timer.stop()
		remove_child(preview_timer)
	for c in get_children():
		c.queue_free()
	yield(get_tree(), "idle_frame")
	rect_size = Vector2(0, 0)
	# Rebuild node
	title = generator.get_type_name()
	# Inputs
	var inputs = generator.get_input_defs()
	for i in range(inputs.size()):
		var input = inputs[i]
		var enable_left = false
		var color_left = Color(0.5, 0.5, 0.5)
		if typeof(input) == TYPE_DICTIONARY:
			if input.type == "rgb":
				enable_left = true
				color_left = Color(0.5, 0.5, 1.0)
			elif input.type == "rgba":
				enable_left = true
				color_left = Color(0.0, 0.5, 0.0, 0.5)
			else:
				enable_left = true
		set_slot(i, enable_left, 0, color_left, false, 0, Color())
		var hsizer : HBoxContainer = HBoxContainer.new()
		hsizer.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		if input.has("label") and input.label != "":
			var label : Label = Label.new()
			label.text = input.label
			hsizer.add_child(label)
		else:
			var control : Control = Control.new()
			control.rect_min_size.y = 16
			hsizer.add_child(control)
			
		add_child(hsizer)
	var input_names_width : int = 0
	for c in get_children():
		var width = c.get_child(0).rect_size.x
		if width > input_names_width:
			input_names_width = width
	if input_names_width > 0:
		input_names_width += 3
	for c in get_children():
		c.get_child(0).rect_min_size.x = input_names_width
	# Parameters
	controls = {}
	var index = -1
	var regex = RegEx.new()
	regex.compile("^(\\d+):(.*)")
	for p in generator.get_parameter_defs():
		if !p.has("name") or !p.has("type"):
			continue
		var control = create_parameter_control(p)
		if control != null:
			var label = p.name
			control.name = label
			controls[control.name] = control
			if p.has("label"):
				label = p.label
			var result = regex.search(label)
			if result:
				index = result.get_string(1).to_int()-1
				label = result.get_string(2)
			else:
				index += 1
			var hsizer : HBoxContainer
			while index >= get_child_count():
				hsizer = HBoxContainer.new()
				hsizer.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
				var empty_control : Control = Control.new()
				empty_control.rect_min_size.x = input_names_width
				hsizer.add_child(empty_control)
				add_child(hsizer)
			hsizer = get_child(index)
			if label != "":
				var label_widget = Label.new()
				label_widget.text = label
				label_widget.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
				hsizer.add_child(label_widget)
			control.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			hsizer.add_child(control)
	initialize_properties()
	# Outputs
	var outputs = generator.get_output_defs()
	var button_width = 0
	output_count = outputs.size()
	for i in range(output_count):
		var output = outputs[i]
		var enable_right = true
		var color_right = Color(0.5, 0.5, 0.5)
		assert(typeof(output) == TYPE_DICTIONARY)
		assert(output.has("type"))
		enable_right = true
		match output.type:
			"rgb": color_right = Color(0.5, 0.5, 1.0)
			"rgba": color_right = Color(0.0, 0.5, 0.0, 0.5)
		set_slot(i, is_slot_enabled_left(i), get_slot_type_left(i), get_slot_color_left(i), enable_right, 0, color_right)
		var hsizer : HBoxContainer
		while i >= get_child_count():
			hsizer = HBoxContainer.new()
			hsizer.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			add_child(hsizer)
		hsizer = get_child(i)
		var has_filler = false
		for c in hsizer.get_children():
			if c.size_flags_horizontal & SIZE_EXPAND != 0:
				has_filler = true
				break
		if !has_filler:
			var empty_control : Control = Control.new()
			empty_control.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
			hsizer.add_child(empty_control)
		var button = preload("res://addons/material_maker/widgets/preview_button.tscn").instance()
		button.size_flags_horizontal = SIZE_SHRINK_END
		button.size_flags_vertical = SIZE_SHRINK_CENTER
		if i == preview_index:
			button.pressed = true
		hsizer.add_child(button)
		button.connect("toggled", self, "on_preview_button", [ i ])
		button_width = button.rect_size.x
	if !outputs.empty():
		for i in range(output_count, get_child_count()):
			var hsizer : HBoxContainer = get_child(i)
			var empty_control : Control = Control.new()
			empty_control.rect_min_size.x = button_width
			hsizer.add_child(empty_control)
	# Preview
	if preview == null:
		preview = TextureRect.new()
	preview.visible = false
	preview_position = get_child_count()
	# Edit buttons
	if generator.model == null:
		var edit_buttons = preload("res://addons/material_maker/nodes/edit_buttons.tscn").instance()
		add_child(edit_buttons)
		edit_buttons.connect_buttons(self, "edit_generator", "load_generator", "save_generator")
	# Preview timer
	if preview_timer == null:
		preview_timer = Timer.new()
		preview_timer.one_shot = true
		preview_timer.connect("timeout", self, "do_update_preview")
	add_child(preview_timer)


func edit_generator():
	if generator.has_method("edit"):
		generator.edit(self)

func update_generator(shader_model):
	generator.set_shader_model(shader_model)
	update_node()
	update_shaders()

func load_generator():
	var dialog = FileDialog.new()
	add_child(dialog)
	dialog.rect_min_size = Vector2(500, 500)
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.mode = FileDialog.MODE_OPEN_FILE
	dialog.add_filter("*.mmg,*.mmn;Material Maker Generator")
	dialog.connect("file_selected", self, "do_load_generator")
	dialog.popup_centered()

func do_load_generator(file_name : String):
	var new_generator = null
	if file_name.ends_with(".mmn"):
		var file = File.new()
		if file.open(file_name, File.READ) == OK:
			new_generator = MMGenShader.new()
			new_generator.set_shader_model(parse_json(file.get_as_text()))
			file.close()
	else:
		new_generator = MMGenLoader.load_gen(file_name)
	if new_generator != null:
		var parent_generator = generator.get_parent()
		parent_generator.replace_generator(generator, new_generator)
		generator = new_generator
		update_node()

func save_generator():
	var dialog = FileDialog.new()
	add_child(dialog)
	dialog.rect_min_size = Vector2(500, 500)
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.mode = FileDialog.MODE_SAVE_FILE
	dialog.add_filter("*.mmg;Material Maker Generator")
	dialog.connect("file_selected", self, "do_save_generator")
	dialog.popup_centered()

func do_save_generator(file_name : String):
	var file = File.new()
	if file.open(file_name, File.WRITE) == OK:
		var data = generator.serialize()
		data.name = file_name.get_file().get_basename()
		data.node_position = { x=0, y=0 }
		file.store_string(to_json(data))
		file.close()

func on_preview_button(pressed : bool, index : int):
	if pressed:
		preview_index = index
		var width
		if preview.visible:
			for i in range(output_count):
				if i != index:
					var line = get_child(i)
					line.get_child(line.get_child_count()-1).pressed = false
			update_preview()
		else:
			var status = update_preview(get_child(0).rect_size.x)
			while status is GDScriptFunctionState:
				status = yield(status, "completed")
	else:
		preview_index = -1
		preview.visible = false
		remove_child(preview)
		rect_size = Vector2(0, 0)

func update_preview(size : int = 0):
	if preview_index == -1:
		return
	if size != 0:
		preview_size = size
	preview_timer.start(0.2)

func do_update_preview():
	var renderer = get_parent().renderer
	var result = generator.render(preview_index, renderer, preview_size)
	while result is GDScriptFunctionState:
		result = yield(result, "completed")
	if preview.texture == null:
		preview.texture = ImageTexture.new()
	result.copy_to_texture(preview.texture)
	result.release()
	if !preview.visible:
		add_child(preview)
		move_child(preview, preview_position)
		preview.visible = true




