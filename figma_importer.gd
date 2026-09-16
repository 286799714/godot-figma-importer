@tool
class_name FigmaImporter
extends Control

const SliceBackground = preload("figma_slice_background.gd")

var script_dir:String = get_script().get_path().get_base_dir()

@export_category("Figma JSON Import")
var is_json_proc:bool = false
## Select the json you exported from Figma.
@export_file("*.json") var document_json_file: set = json_load
## Process the JSON file to populate the Page list.
@export var process_json:bool = false: set = run_arrange
## Select the page from your Figma document you want to load.
@export var SelectPage : String : set = changePageSelect
## Select the Frame from the selected page you want to import. Currently the importer will display a list of top level frames.
@export var SelectFrame : String :
	set(value):
		SelectFrame = value
		notify_property_list_changed()
@export_group("Import Options")
## Keep the exported positions and sizes. Disable to convert Figma auto layout into Godot containers.
@export var preserve_figma_layout:bool = true
## Combine three-part and nine-part image backgrounds into one texture to avoid seams.
@export var merge_sliced_backgrounds:bool = true
## Select the folder to where you copied your fonts. Leaving this empy will result in using Godot's default font.
@export_dir var fonts_folder
## Select the folder to where you copied your images. Leaving this empty will result in images not being imported.
@export_dir var images_folder : 
	set(value):
		images_folder = value
		if images_folder == null || images_folder == "" || images_folder == " ":
			autoPlaceImages = false
		else: 
			autoPlaceImages = true
		notify_property_list_changed()
## Select or deselect if you want the importer to automatically import images.
@export var autoPlaceImages:bool = false
## Not required. Select the json file with the details of which instantiated scene should be used with specific frame ids.
@export_file("*.json") var component_json_dicionary: set = component_json_load
## This will instantiation child scenes from a matching id list of Figma components. This requires the id numbers match between Figma and Godot.
@export var compInstToScenes:bool = false
@export_group("Import Layouts")
## Renders the listed frames to the current node.
@export var importFrames:bool = false: set = renderFrameArray

var page_hints:String
var frame_hints:String
var current_depth:int = 0
var processed_json_dict:Dictionary
var is_comp_json:bool = false
var component_dictionary:Dictionary

func _validate_property(property : Dictionary) -> void:
	if property.name == &"SelectPage":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = page_hints
	if property.name == &"SelectFrame":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = frame_hints
	if property.name == "autoPlaceImages" and (images_folder == null || images_folder == ""):
		property.usage |= PROPERTY_USAGE_READ_ONLY
	if property.name == "compInstToScenes" and (component_json_dicionary == null || component_json_dicionary == ""):
		property.usage |= PROPERTY_USAGE_READ_ONLY
	if property.name == "importFrames" and (SelectFrame == null || SelectFrame == "" || SelectFrame == "Select Frame"):
		property.usage |= PROPERTY_USAGE_READ_ONLY

func changePageSelect(_stuff):
	SelectPage = _stuff
	if SelectPage != "Select Page" && SelectPage != "" && is_json_proc:
		var my_string = strip_to_id(SelectPage)
		frame_hints = "Select Frame,"
		SelectFrame = "Select Frame"
		for p_id in processed_json_dict[my_string]["children"]:
			frame_hints += processed_json_dict[p_id]["name"]+" xIDx"+p_id+"x,"
	notify_property_list_changed()

func component_json_load(_newVar):
	if Engine.is_editor_hint():
		component_json_dicionary = _newVar
		if component_json_dicionary != null:
			is_comp_json = true
			#Load the file.
			var data_file = FileAccess.open(_newVar, FileAccess.READ)
			#Parse the json file.
			var data_parsed = JSON.parse_string(data_file.get_as_text())
			component_dictionary = data_parsed
			compInstToScenes = true
		else:
			print("no json file")
			compInstToScenes = false
		notify_property_list_changed()

func json_load(_stuff):
	if Engine.is_editor_hint():
		print(script_dir)
		document_json_file = _stuff
		notify_property_list_changed()

func run_arrange(_newVar):
	if document_json_file != null:
		# Reprocessing must not retain nodes from an earlier document or failed import.
		processed_json_dict.clear()
		is_json_proc = true
		#Load the file.
		var data_file = FileAccess.open(document_json_file, FileAccess.READ)
		#Parse the json file.
		var data_parsed = JSON.parse_string(data_file.get_as_text())
		page_hints = "Select Page,"
		SelectPage = "Select Page"
		frame_hints = ""
		SelectFrame = ""
		if data_parsed.has("children"):
			cycle_children(data_parsed["children"], str(data_parsed.get("id", "")))
		else:
			print("Empty document")
	else:
		print("no json file")

func cycle_children(what_to_process, parent_id:String = ""):
	pass
	if what_to_process.size() > 0:
		for new_item in what_to_process.size():
			var fig_id = test_key(what_to_process[new_item],"id")
			var fig_name = test_key(what_to_process[new_item],"name")
			# Frame exports from older exporters omit parent on the page wrapper.
			# The enclosing children array already supplies the missing relationship.
			var fig_parent:String = parent_id
			var parent_data = what_to_process[new_item].get("parent")
			if parent_data is Dictionary and parent_data.get("id") is String:
				if not parent_data["id"].is_empty():
					fig_parent = parent_data["id"]
			var fig_children:Array
			var fig_comp_props:Dictionary
			var fig_comp_prop_defs:Dictionary
			var fig_master_comp:String
			if what_to_process[new_item]["type"] == "PAGE":
				page_hints += fig_name+" xIDx"+fig_id+"x,"
				notify_property_list_changed()
			elif what_to_process[new_item]["type"] == "COMPONENT":
				if what_to_process[new_item].has("componentPropertyDefinitions"):
					fig_comp_prop_defs = what_to_process[new_item]["componentPropertyDefinitions"]
			elif what_to_process[new_item]["type"] == "INSTANCE":
				fig_master_comp = what_to_process[new_item]["masterComponent"]["id"]
				if what_to_process[new_item].has("componentProperties"):
					fig_comp_props = what_to_process[new_item]["componentProperties"]
			var with_child:bool = false
			if what_to_process[new_item].has("children"):
				with_child = true
				for new_child in what_to_process[new_item]["children"].size():
					fig_children.append(what_to_process[new_item]["children"][new_child]["id"])
			processed_json_dict[fig_id] = {
				"type" : test_key(what_to_process[new_item],"type"),
				"name" : fig_name,
				"parent": fig_parent,
				"x" : test_key(what_to_process[new_item],"x"),
				"y" : test_key(what_to_process[new_item],"y"),
				"width" : test_key(what_to_process[new_item],"width"),
				"height" : test_key(what_to_process[new_item],"height"),
				"minWidth" : test_key(what_to_process[new_item],"minWidth"),
				"minHeight" : test_key(what_to_process[new_item],"minHeight"),
				"maxWidth" : test_key(what_to_process[new_item],"maxWidth"),
				"maxHeight" : test_key(what_to_process[new_item],"maxHeight"),
				"rotation" : test_key(what_to_process[new_item],"rotation"),
				"fills" : test_key(what_to_process[new_item],"fills"),
				"padding" : [test_key(what_to_process[new_item],"paddingTop"),test_key(what_to_process[new_item],"paddingRight"),test_key(what_to_process[new_item],"paddingBottom"),test_key(what_to_process[new_item],"paddingLeft")],
				"corner_radius" : [test_key(what_to_process[new_item],"topLeftRadius"),test_key(what_to_process[new_item],"topRightRadius"),test_key(what_to_process[new_item],"bottomRightRadius"),test_key(what_to_process[new_item],"bottomLeftRadius")],
				"border_weights" : [test_key(what_to_process[new_item],"strokeTopWeight"),test_key(what_to_process[new_item],"strokeRightWeight"),test_key(what_to_process[new_item],"strokeBottomWeight"),test_key(what_to_process[new_item],"strokeLeftWeight")],
				"border_color" : test_key(what_to_process[new_item],"strokes"),
				"stroke_weight" : test_key(what_to_process[new_item],"strokeWeight"),
				"layout_wrap" : test_key(what_to_process[new_item],"layoutWrap"),
				"layout_mode" : test_key(what_to_process[new_item],"layoutMode"),
				"layout_horiz_sizing" : test_key(what_to_process[new_item],"layoutSizingHorizontal"),
				"layout_vert_sizing" : test_key(what_to_process[new_item],"layoutSizingVertical"),
				"hLayout_Align": proc_hlayoutAlign(test_key(what_to_process[new_item],"primaryAxisAlignItems")),
				"vLayout_Align": proc_vlayoutAlign(test_key(what_to_process[new_item],"counterAxisAlignItems")),
				"clip_content" : test_key(what_to_process[new_item],"clipsContent"),
				"horizontalAnchor" : proc_halignments(test_key(what_to_process[new_item],"constraints")),
				"verticalAnchor" : proc_valignments(test_key(what_to_process[new_item],"constraints")),
				"children" : fig_children,
				"gap_spacing" : test_key(what_to_process[new_item],"itemSpacing"),
				"vertical_gap_spacing" : test_key(what_to_process[new_item],"counterAxisSpacing"),
				"master_comp" : fig_master_comp,
				"component_properties" : fig_comp_props,
				"component_property_defs" : fig_comp_prop_defs,
				"textAlignHorizontal": test_key(what_to_process[new_item],"textAlignHorizontal"),
				"textAlignVertical": test_key(what_to_process[new_item],"textAlignVertical"),
				"textTruncation": test_key(what_to_process[new_item],"textTruncation"),
				"characters": test_key(what_to_process[new_item],"characters"),
				"fontName": test_key(what_to_process[new_item],"fontName"),
				"fontWeight": test_key(what_to_process[new_item],"fontWeight"),
				"fontSize": test_key(what_to_process[new_item],"fontSize"),
				"fontStrokeWeight": test_key(what_to_process[new_item],"strokeWeight"),
				"letterSpacing": test_key(what_to_process[new_item],"letterSpacing"),
				"textAutoResize": test_key(what_to_process[new_item],"textAutoResize"),
				"visible": what_to_process[new_item].get("visible", true),
				"opacity": what_to_process[new_item].get("opacity", 1.0),
				"effects": what_to_process[new_item].get("effects", []),
				"blendMode": what_to_process[new_item].get("blendMode", "NORMAL"),
				"reverse_z": what_to_process[new_item].get("itemReverseZIndex", false),
				"fillGeometry": what_to_process[new_item].get("fillGeometry", []),
				"relativeTransform": test_key(what_to_process[new_item],"relativeTransform"),
				"absoluteTransform": test_key(what_to_process[new_item],"absoluteTransform")
			}
			if with_child:
				cycle_children(what_to_process[new_item]["children"], fig_id)

func renderFrameArray(_stuff):
	var frame_id = strip_to_id(SelectFrame)
	renderFrameAndContents(frame_id,self,true)

func renderChildFrames(frame,parent):
	var children:Array = processed_json_dict[frame]["children"].duplicate()
	if processed_json_dict[frame].get("reverse_z", false):
		children.reverse()
	for object_id in children:
		renderFrameAndContents(object_id,parent,false)

func renderFrameAndContents(object_id,parent,position_override:bool):
	var the_type = processed_json_dict[object_id]["type"]
	if the_type == "TEXT":
		renderTextFrame(parent,object_id)
	elif the_type == "LINE":
		renderLine(parent,object_id)
	elif the_type == "INSTANCE" && compInstToScenes:
		place_component_inst(parent,object_id)
	else:
		var newFrame
		var isRectangle:bool = false
		var sliced:Dictionary = {}
		if preserve_figma_layout and merge_sliced_backgrounds and autoPlaceImages and images_folder is String:
			sliced = SliceBackground.compose(processed_json_dict[object_id], processed_json_dict, images_folder)
		if the_type == "RECTANGLE" or not sliced.is_empty():
			isRectangle = true
		if isRectangle:
			newFrame = DesignerImagePanel.new()
		else:
			newFrame = DesignerFrame.new()
		newFrame.name = processed_json_dict[object_id]["name"]+" xIDx"+ make_safeName(object_id)+"x"
		parent.add_child(newFrame)
		newFrame.set_owner(import_scene_owner())
		newFrame.use_solid_fill = false
		if not sliced.is_empty():
			newFrame.fill_texture = sliced.texture
			newFrame.textureSizeMode = "Stretch"
			newFrame.set_meta("figma_slice_children", sliced.children)
		if !isRectangle:
			newFrame.scrollingMode = "None"
			var newControl = Control.new()
			newControl.name = "InnerContainer"
			newFrame.add_child(newControl)
			newFrame.inner_container = newControl.get_path()
			newFrame.get_node(newFrame.inner_container).set_owner(import_scene_owner())
		newFrame.the_id = object_id
		newFrame.widthSizeMode = "FIXED" if preserve_figma_layout else processed_json_dict[object_id]["layout_horiz_sizing"]
		newFrame.heightSizeMode = "FIXED" if preserve_figma_layout else processed_json_dict[object_id]["layout_vert_sizing"]
		if processed_json_dict[object_id]["minWidth"] != null:
			newFrame.minSize.x = processed_json_dict[object_id]["minWidth"]
		else:
			newFrame.minSize.x = 0.0
		if processed_json_dict[object_id]["minHeight"] != null:
			newFrame.minSize.y = processed_json_dict[object_id]["minHeight"]
		else:
			newFrame.minSize.y = 0.0
		if processed_json_dict[object_id]["maxWidth"] != null:
			newFrame.maxSize.x = processed_json_dict[object_id]["maxWidth"]
		else:
			newFrame.maxSize.x = 100000.0
		if processed_json_dict[object_id]["maxHeight"] != null:
			newFrame.maxSize.y = processed_json_dict[object_id]["maxHeight"]
		else:
			newFrame.maxSize.y = 100000.0
		newFrame.set_deferred("size", Vector2(processed_json_dict[object_id]["width"],processed_json_dict[object_id]["height"]))
		if processed_json_dict[object_id]["layout_horiz_sizing"] == "FIXED" && processed_json_dict[object_id]["minWidth"] == null:
			newFrame.minSize.x = processed_json_dict[object_id]["width"]
		if processed_json_dict[object_id]["layout_vert_sizing"] == "FIXED" && processed_json_dict[object_id]["minHeight"] == null:
			newFrame.minSize.y = processed_json_dict[object_id]["height"]
		if position_override:
			newFrame.set_deferred("position", Vector2(0.0,0.0))
		else:
			newFrame.set_deferred("position", Vector2(processed_json_dict[object_id]["x"],processed_json_dict[object_id]["y"]))
		# Use one matrix decomposition for rotations and both mirror directions.
		apply_figma_geometry.call_deferred(newFrame, object_id, position_override)
		if !isRectangle:
			# Figma child coordinates already include padding; adding it again shifts every child.
			newFrame.padding = [0, 0, 0, 0] if preserve_figma_layout else processed_json_dict[object_id]["padding"]
		newFrame.fill_color = Color(0.0,0.0,0.0,0.0)
		var vector_rendered:bool = false
		if the_type in ["POLYGON", "VECTOR", "STAR", "BOOLEAN_OPERATION"]:
			vector_rendered = render_vector_geometry(newFrame, object_id)
			if not vector_rendered:
				place_error_image(newFrame)
		elif processed_json_dict[object_id]["fills"] != null && processed_json_dict[object_id]["fills"] != []:
			process_colors(processed_json_dict[object_id]["fills"],newFrame)
		var stroke = first_visible_paint(processed_json_dict[object_id]["border_color"], "SOLID")
		if not stroke.is_empty():
			newFrame.border_color = paint_color(stroke)
			newFrame.border_weights = processed_json_dict[object_id]["border_weights"]
		newFrame.corner_radius = processed_json_dict[object_id]["corner_radius"]
		if !isRectangle and not preserve_figma_layout:
			if processed_json_dict[object_id]["layout_wrap"] != null:
				newFrame.layoutWrap = processed_json_dict[object_id]["layout_wrap"]
				if processed_json_dict[object_id]["layout_wrap"] == "NO_WRAP":
					newFrame.layoutMode = processed_json_dict[object_id]["layout_mode"]
			if processed_json_dict[object_id]["gap_spacing"] != null:
				newFrame.spacing = processed_json_dict[object_id]["gap_spacing"]
			if processed_json_dict[object_id]["vertical_gap_spacing"] != null:
				newFrame.secondary_spacing = processed_json_dict[object_id]["vertical_gap_spacing"]
		if processed_json_dict[object_id]["clip_content"] != null:
			newFrame.clipFrameContents = processed_json_dict[object_id]["clip_content"]
		if not preserve_figma_layout:
			newFrame.set_deferred("horizontalAnchor", processed_json_dict[object_id]["horizontalAnchor"])
			newFrame.set_deferred("verticalAnchor", processed_json_dict[object_id]["verticalAnchor"])
			newFrame.set_deferred("hLayoutAlign", processed_json_dict[object_id]["hLayout_Align"])
			newFrame.set_deferred("vLayoutAlign", processed_json_dict[object_id]["vLayout_Align"])
		if !isRectangle:
			if processed_json_dict[object_id]["children"] != null && processed_json_dict[object_id]["children"] != []:
				renderChildFrames(object_id,newFrame.get_node(newFrame.inner_container))
				if vector_rendered and the_type == "BOOLEAN_OPERATION":
					# The composite path already contains the boolean result.
					newFrame.get_node(newFrame.inner_container).hide()

func import_scene_owner() -> Node:
	var scene_root = get_tree().get_edited_scene_root()
	return scene_root if scene_root != null else self

func apply_figma_geometry(control:Control, object_id:String, is_root:bool = false) -> void:
	var data:Dictionary = processed_json_dict[object_id]
	var transform:Transform2D = Transform2D.IDENTITY
	var relative = data.get("relativeTransform")
	if relative is Array and FigmaGradientTexture2D.can_transform_from_array(relative):
		transform = FigmaGradientTexture2D.transform_from_array(relative)
	else:
		transform.origin = Vector2(data.get("x", 0.0), data.get("y", 0.0))
	# Boolean-operation children can be exported in their ancestor's coordinate space.
	# Deriving the local transform from absolute matrices handles those nodes as well.
	var absolute = data.get("absoluteTransform")
	var parent_data:Dictionary = processed_json_dict.get(data.get("parent", ""), {})
	var parent_absolute = parent_data.get("absoluteTransform")
	if absolute is Array and parent_absolute is Array:
		transform = FigmaGradientTexture2D.transform_from_array(parent_absolute).affine_inverse() * FigmaGradientTexture2D.transform_from_array(absolute)
	if is_root:
		transform = Transform2D.IDENTITY
	control.pivot_offset = Vector2.ZERO
	control.rotation = transform.get_rotation()
	control.scale = transform.get_scale()
	control.position = transform.origin
	control.visible = data.get("visible", true)
	control.modulate.a = data.get("opacity", 1.0)
	if preserve_figma_layout:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.size = Vector2(data["width"], data["height"])

func first_visible_paint(paints, required_type:String = "") -> Dictionary:
	if paints is Array:
		for paint in paints:
			if paint is Dictionary and paint.get("visible", true) and (required_type.is_empty() or paint.get("type") == required_type):
				return paint
	return {}

func paint_color(paint:Dictionary) -> Color:
	var color_data:Dictionary = paint.get("color", {})
	return Color(color_data.get("r", 0.0), color_data.get("g", 0.0), color_data.get("b", 0.0), color_data.get("a", 1.0) * paint.get("opacity", 1.0))

func paint_gradient(paint:Dictionary) -> GradientTexture2D:
	var colors:PackedColorArray = []
	var offsets:PackedFloat32Array = []
	for stop in paint.get("gradientStops", []):
		colors.append(paint_color({"color": stop["color"], "opacity": paint.get("opacity", 1.0)}))
		offsets.append(stop["position"])
	var gradient = Gradient.new()
	gradient.colors = colors
	gradient.offsets = offsets
	var texture = FigmaGradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL if paint.get("type") == "GRADIENT_RADIAL" else GradientTexture2D.FILL_LINEAR
	texture.figma_transform_array = paint.get("gradientTransform", [[1, 0, 0], [0, 1, 0]])
	return texture

func render_vector_geometry(control:Control, object_id:String) -> bool:
	var data:Dictionary = processed_json_dict[object_id]
	var geometry = data.get("fillGeometry")
	if not geometry is Array or geometry.is_empty() or not data["fills"] is Array:
		return false
	var definitions:String = ""
	var paths:String = ""
	var paints:Array = data["fills"].duplicate()
	paints.reverse()
	for index in paints.size():
		var paint:Dictionary = paints[index]
		if not paint.get("visible", true):
			continue
		var fill:String
		var opacity:float = 1.0
		if paint.get("type") == "SOLID":
			var color = paint_color(paint)
			fill = "#" + color.to_html(false)
			opacity = color.a
		elif paint.get("type") == "GRADIENT_LINEAR":
			var gradient_texture = paint_gradient(paint)
			var start = gradient_texture.fill_from
			var end = gradient_texture.fill_to
			var gradient_id:String = "gradient_%d" % index
			definitions += '<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">' % [gradient_id, start.x, start.y, end.x, end.y]
			for stop in paint.get("gradientStops", []):
				var color = paint_color({"color": stop["color"], "opacity": paint.get("opacity", 1.0)})
				definitions += '<stop offset="%s" stop-color="#%s" stop-opacity="%s"/>' % [stop["position"], color.to_html(false), color.a]
			definitions += "</linearGradient>"
			fill = "url(#%s)" % gradient_id
		else:
			continue
		for path in geometry:
			var rule:String = "evenodd" if path.get("windingRule") == "EVENODD" else "nonzero"
			paths += '<path d="%s" fill="%s" fill-opacity="%s" fill-rule="%s"/>' % [str(path["data"]).xml_escape(), fill, opacity, rule]
	if paths.is_empty():
		return false
	var svg:String = '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s"><defs>%s</defs>%s</svg>' % [data["width"], data["height"], data["width"], data["height"], definitions, paths]
	var raster = Image.new()
	if raster.load_svg_from_string(svg, 2.0) != OK:
		return false
	control.fill_texture = ImageTexture.create_from_image(raster)
	control.textureSizeMode = "Stretch"
	return true

func checkParentLayoutNone(theParent):
	if processed_json_dict[theParent]["layout_mode"] != null:
		print(processed_json_dict[theParent]["name"])
		if processed_json_dict[theParent]["layout_mode"] == "NONE":
			return false
		else:
			return true
	else:
		return false

func process_colors(theColorsArray,theNode):
	pass
	for aFill in theColorsArray.size():
		if theColorsArray[aFill]["visible"] == true:
			match theColorsArray[aFill]["type"]:
				"SOLID":
					theNode.fill_color = Color(theColorsArray[aFill]["color"]["r"],theColorsArray[aFill]["color"]["g"],theColorsArray[aFill]["color"]["b"],theColorsArray[aFill]["opacity"])
					theNode.use_solid_fill = true
				"GRADIENT_LINEAR":
					var gradient = Gradient.new() 
					for colorStop in theColorsArray[aFill]["gradientStops"].size():
						gradient.add_point(theColorsArray[aFill]["gradientStops"][colorStop]["position"], Color(theColorsArray[aFill]["gradientStops"][colorStop]["color"]["r"],theColorsArray[aFill]["gradientStops"][colorStop]["color"]["g"],theColorsArray[aFill]["gradientStops"][colorStop]["color"]["b"],theColorsArray[aFill]["gradientStops"][colorStop]["color"]["a"]))
					gradient.remove_point(1)
					gradient.remove_point(0)
					var gradient_texture = FigmaGradientTexture2D.new()
					gradient_texture.gradient = gradient
					gradient_texture.fill = GradientTexture2D.FILL_LINEAR
					gradient_texture.width = 64
					gradient_texture.height = 64
					gradient_texture.figma_transform_array = theColorsArray[aFill]["gradientTransform"]
					theNode.fill_gradient = gradient_texture
				"GRADIENT_RADIAL":
					var gradient = Gradient.new() 
					for colorStop in theColorsArray[aFill]["gradientStops"].size():
						gradient.add_point(theColorsArray[aFill]["gradientStops"][colorStop]["position"], Color(theColorsArray[aFill]["gradientStops"][colorStop]["color"]["r"],theColorsArray[aFill]["gradientStops"][colorStop]["color"]["g"],theColorsArray[aFill]["gradientStops"][colorStop]["color"]["b"],theColorsArray[aFill]["gradientStops"][colorStop]["color"]["a"]))
					gradient.remove_point(1)
					gradient.remove_point(0)
					var gradient_texture = FigmaGradientTexture2D.new()
					gradient_texture.gradient = gradient
					gradient_texture.fill = GradientTexture2D.FILL_RADIAL
					gradient_texture.width = 64
					gradient_texture.height = 64
					gradient_texture.figma_transform_array = theColorsArray[aFill]["gradientTransform"]
					theNode.fill_gradient = gradient_texture
				"IMAGE":
					if images_folder != null && images_folder != "" && autoPlaceImages:
						var file_path = images_folder + "/"+theColorsArray[aFill]["imageHash"]+".png"
						if FileAccess.file_exists(file_path):
							pass
							var image_texture = load(file_path) as Texture
							theNode.fill_texture = image_texture
							match theColorsArray[aFill]["scaleMode"]:
								"FILL":
									theNode.textureSizeMode = "Fill"
								"FIT":
									theNode.textureSizeMode = "Fit"
								"TILE":
									theNode.textureSizeMode = "Keep Size"
									theNode.tile_texture = true
									theNode.zoom = theColorsArray[aFill]["scalingFactor"]
								"CROP":
									# Exported PNGs already contain the crop. Applying the
									# source scalingFactor again shrinks decorative images.
									theNode.textureSizeMode = "Fill"
						else:
							place_error_image(theNode)

func place_error_image(theNode)->void:
	var errorFile:String = script_dir + "/error_texture.png"
	var image_texture = load(errorFile) as Texture
	theNode.fill_texture = image_texture
	theNode.textureSizeMode = "Fill"

func renderRectangle(parent,p_id):
	pass
	print(p_id)

func renderLine(parent,p_id):
	pass
	var newFrame = HSeparator.new()
	newFrame.name = processed_json_dict[p_id]["name"]+" xIDx"+ make_safeName(p_id)+"x"
	parent.add_child(newFrame)
	newFrame.set_owner(import_scene_owner())
	newFrame.set_deferred("size", Vector2(processed_json_dict[p_id]["width"],processed_json_dict[p_id]["stroke_weight"]))
	if processed_json_dict[p_id]["layout_horiz_sizing"] == "FIXED" && processed_json_dict[p_id]["minWidth"] == null:
		newFrame.set_deferred("custom_minimum_size:x", processed_json_dict[p_id]["width"])
	if processed_json_dict[p_id]["layout_vert_sizing"] == "FIXED" && processed_json_dict[p_id]["minHeight"] == null:
		newFrame.set_deferred("custom_minimum_size:y", processed_json_dict[p_id]["height"])
	newFrame.set_deferred("position", Vector2(processed_json_dict[p_id]["x"],processed_json_dict[p_id]["y"]))
	newFrame.set_deferred("rotation_degrees", processed_json_dict[p_id]["rotation"] * -1)
	newFrame.set_deferred("center_rotation", true)
	var stylebox_line = StyleBoxLine.new()
	stylebox_line.set("color",Color(processed_json_dict[p_id]["border_color"][0]["color"]["r"],processed_json_dict[p_id]["border_color"][0]["color"]["g"],processed_json_dict[p_id]["border_color"][0]["color"]["b"]))
	stylebox_line.set("thickness", processed_json_dict[p_id]["stroke_weight"])
	stylebox_line.set("grow_begin", 0)
	stylebox_line.set("grow_end", 0)
	newFrame.add_theme_stylebox_override("separator", stylebox_line)
	newFrame.set_deferred("horizontalAnchor", processed_json_dict[p_id]["horizontalAnchor"])
	newFrame.set_deferred("verticalAnchor", processed_json_dict[p_id]["verticalAnchor"])
	newFrame.set_deferred("hLayoutAlign", processed_json_dict[p_id]["hLayout_Align"])
	newFrame.set_deferred("vLayoutAlign", processed_json_dict[p_id]["vLayout_Align"])

func renderTextFrame(parent,p_id):
	var newFrame = Label.new()
	var newLabelSettings = LabelSettings.new()
	newLabelSettings.line_spacing = 0
	if fonts_folder != null and fonts_folder != "" and processed_json_dict[p_id]["fontName"] is Dictionary:
		var font_name = str(processed_json_dict[p_id]["fontName"]["family"]).replace(" ", "")
		var font_style = str(processed_json_dict[p_id]["fontName"]["style"]).replace(" ", "")
		var font_location:String = fonts_folder + "/" + font_name + "_" + font_style + ".ttf"
		if FileAccess.file_exists(font_location):
			newLabelSettings.font = load(font_location)
	newLabelSettings.font_size = processed_json_dict[p_id]["fontSize"]
	var spacing = processed_json_dict[p_id].get("letterSpacing")
	if spacing is Dictionary and spacing.get("value", 0.0) != 0.0:
		var variation = FontVariation.new()
		variation.base_font = newLabelSettings.font
		var pixels:float = spacing["value"]
		if spacing.get("unit") == "PERCENT":
			pixels *= newLabelSettings.font_size / 100.0
		variation.spacing_glyph = roundi(pixels)
		newLabelSettings.font = variation
	var fill = first_visible_paint(processed_json_dict[p_id]["fills"])
	newLabelSettings.font_color = Color.TRANSPARENT
	if fill.get("type") == "SOLID":
		newLabelSettings.font_color = paint_color(fill)
	elif fill.get("type") in ["GRADIENT_LINEAR", "GRADIENT_RADIAL"]:
		newLabelSettings.font_color = Color.WHITE
		var gradient_material = ShaderMaterial.new()
		gradient_material.shader = load(script_dir + "/shader/text_gradient.gdshader")
		gradient_material.set_shader_parameter("gradient_texture", paint_gradient(fill))
		gradient_material.set_shader_parameter("label_size", Vector2(processed_json_dict[p_id]["width"], processed_json_dict[p_id]["height"]))
		newFrame.material = gradient_material
	var stroke = first_visible_paint(processed_json_dict[p_id]["border_color"], "SOLID")
	if not stroke.is_empty():
		newLabelSettings.outline_color = paint_color(stroke)
		newLabelSettings.outline_size = roundi(processed_json_dict[p_id]["fontStrokeWeight"])
	newFrame.name = processed_json_dict[p_id]["name"]+"  xIDx"+ make_safeName(p_id)+"x"
	parent.add_child(newFrame)
	newFrame.set_label_settings(newLabelSettings)
	newFrame.set_owner(import_scene_owner())
	newFrame.text = processed_json_dict[p_id]["characters"]
	update_textHAlign(processed_json_dict[p_id]["textAlignHorizontal"],newFrame)
	update_textVAlign(processed_json_dict[p_id]["textAlignVertical"],newFrame)
	if preserve_figma_layout:
		newFrame.clip_text = true
		newFrame.autowrap_mode = TextServer.AUTOWRAP_OFF if processed_json_dict[p_id].get("textAutoResize") == "WIDTH_AND_HEIGHT" else TextServer.AUTOWRAP_WORD_SMART
		# Figma and Godot round font descent differently. Preserve a single auto-sized
		# line's exported line box without scaling or moving its glyphs.
		newFrame.size = Vector2(processed_json_dict[p_id]["width"], processed_json_dict[p_id]["height"])
		if newFrame.get_line_count() == 1 and not newFrame.text.contains("\n"):
			var line_difference:int = roundi(processed_json_dict[p_id]["height"] - newFrame.get_line_height())
			if line_difference < 0:
				var line_font = FontVariation.new()
				line_font.base_font = newLabelSettings.font
				line_font.spacing_bottom = line_difference
				newLabelSettings.font = line_font
		apply_figma_geometry.call_deferred(newFrame, p_id)
		return
	newFrame.set_deferred("size", Vector2(processed_json_dict[p_id]["width"],processed_json_dict[p_id]["height"]))
	apply_figma_geometry.call_deferred(newFrame, p_id)
	if processed_json_dict[p_id]["layout_horiz_sizing"] != "FILL":
		newFrame.set_deferred("custom_minimum_size", Vector2(processed_json_dict[p_id]["width"],processed_json_dict[p_id]["height"]))
	else:
		newFrame.set_deferred("custom_minimum_size", Vector2(1.0,processed_json_dict[p_id]["height"]))
	newFrame.set_deferred("autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
	set_textwSize_fup(processed_json_dict[p_id]["layout_horiz_sizing"],newFrame)
	set_texthSize_fup(processed_json_dict[p_id]["layout_vert_sizing"],newFrame)
	
func place_component_inst(parent,p_id):
	var adjustedID = make_safeName(processed_json_dict[p_id]["master_comp"])
	var newComp = load(component_dictionary[adjustedID])
	var newFrame = newComp.instantiate()
	newFrame.name = processed_json_dict[p_id]["name"]+" xIDx"+ make_safeName(p_id)+"x"
	for key in processed_json_dict[p_id]["component_properties"].keys():
		if newFrame.has_meta(remove_after_hashtag(key)) != null:
			newFrame.set_deferred(remove_after_hashtag(key), processed_json_dict[p_id]["component_properties"][key]["value"])
	parent.add_child(newFrame)
	newFrame.set_owner(import_scene_owner())
	newFrame.widthSizeMode = processed_json_dict[p_id]["layout_horiz_sizing"]
	newFrame.heightSizeMode = processed_json_dict[p_id]["layout_vert_sizing"]
	if processed_json_dict[p_id]["minWidth"] != null:
		newFrame.minSize.x = processed_json_dict[p_id]["minWidth"]
	else:
		newFrame.minSize.x = 0.0
	if processed_json_dict[p_id]["minHeight"] != null:
		newFrame.minSize.y = processed_json_dict[p_id]["minHeight"]
	else:
		newFrame.minSize.y = 0.0
	if processed_json_dict[p_id]["maxWidth"] != null:
		newFrame.maxSize.x = processed_json_dict[p_id]["maxWidth"]
	else:
		newFrame.maxSize.x = 100000.0
	if processed_json_dict[p_id]["maxHeight"] != null:
		newFrame.maxSize.y = processed_json_dict[p_id]["maxHeight"]
	else:
		newFrame.maxSize.y = 100000.0
	newFrame.set_deferred("size", Vector2(processed_json_dict[p_id]["width"],processed_json_dict[p_id]["height"]))
	if processed_json_dict[p_id]["layout_horiz_sizing"] == "FIXED" && processed_json_dict[p_id]["minWidth"] == null:
		newFrame.minSize.x = processed_json_dict[p_id]["width"]
	if processed_json_dict[p_id]["layout_vert_sizing"] == "FIXED" && processed_json_dict[p_id]["minHeight"] == null:
		newFrame.minSize.y = processed_json_dict[p_id]["height"]
	newFrame.set_deferred("position", Vector2(processed_json_dict[p_id]["x"],processed_json_dict[p_id]["y"]))
	newFrame.set_deferred("rotation_degrees", processed_json_dict[p_id]["rotation"] * -1)
	if processed_json_dict[p_id]["relativeTransform"][0][0] < 0:
		newFrame.scale.y *= -1
	if processed_json_dict[p_id]["relativeTransform"][1][1] < 0:
		newFrame.scale.y *= -1
	newFrame.set_deferred("center_rotation", true)
	newFrame.padding = processed_json_dict[p_id]["padding"]
	newFrame.widthSizeMode = processed_json_dict[p_id]["layout_horiz_sizing"]
	newFrame.heightSizeMode = processed_json_dict[p_id]["layout_vert_sizing"]
	newFrame.set_deferred("horizontalAnchor", processed_json_dict[p_id]["horizontalAnchor"])
	newFrame.set_deferred("verticalAnchor", processed_json_dict[p_id]["verticalAnchor"])
	pass

func remove_after_hashtag(input_string: String) -> String: 
	var hashtag_index = input_string.find("#") 
	if hashtag_index != -1: 
		return input_string.substr(0, hashtag_index) 
	return input_string

func changeTheFont(theFontName:String):
	pass
	var current_font = null
	var unused_font = load(fonts_folder+"/" + theFontName + ".ttf")
	var dynamicfont = get("custom_fonts/font")
	current_font = dynamicfont.font_data
	dynamicfont.font_data = unused_font
	unused_font = current_font

func update_textHAlign(_theVar,theNode):
	match _theVar:
		"LEFT":
			theNode.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		"CENTER":
			theNode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		"RIGHT":
			theNode.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func update_textVAlign(_theVar,theNode):
	match _theVar:
		"TOP":
			theNode.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		"CENTER":
			theNode.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		"BOTTOM":
			theNode.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func set_textwSize_fup(widthSizeMode,theNode)->void:
	match widthSizeMode:
		"HUG":
			theNode.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			theNode.size.x = 0.0
		"FIXED":
			theNode.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		"FILL":
			theNode.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func set_texthSize_fup(heightSizeMode,theNode)->void:
	match heightSizeMode:
		"HUG":
			theNode.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			theNode.size.y = 0.0
		"FIXED":
			theNode.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		"FILL":
			theNode.size_flags_vertical = Control.SIZE_EXPAND_FILL


func test_key(the_dict,the_key:String):
	if the_dict.has(the_key):
		return the_dict[the_key]

func strip_to_id(input_string:String):
	var start_pos = input_string.find("xIDx") + 4 
	var end_pos = input_string.rfind("x") 
	if start_pos < end_pos: 
		return input_string.substr(start_pos, end_pos - start_pos) 
	else:
		print("no id")

func make_safeName(the_name:String):
	var my_string:String = the_name
	my_string = my_string.replace(":","_")
	return(my_string)
	
func remove_spaces(incoming_string:String):
	var my_string:String = incoming_string
	my_string = my_string.replace(" ","")
	return(my_string)

func proc_halignments(_dicInfo):
	var newString:String = "Left"
	if _dicInfo != null:
		var whatProc = _dicInfo["horizontal"]
		match whatProc:
			"MIN":
				newString = "Left"
			"MAX":
				newString = "Right"
			"STRETCH":
				newString = "Left and Right"
			"CENTER":
				newString = "Center"
			"SCALE":
				newString = "Scale"
	return newString

func proc_valignments(_dicInfo):
	var newString:String = "Top"
	if _dicInfo != null:
		var whatProc = _dicInfo["vertical"]
		match whatProc:
			"MIN":
				newString = "Top"
			"MAX":
				newString = "Bottom"
			"STRETCH":
				newString = "Top and Bottom"
			"CENTER":
				newString = "Center"
			"SCALE":
				newString = "Scale"
	return newString

func proc_hlayoutAlign(_theWhat):
	pass
	var newString:String = "Left"
	if _theWhat != null:
		match _theWhat:
			"MIN":
				newString = "Left"
			"MAX":
				newString = "Right"
			"CENTER":
				newString = "Center"
	return newString
	
func proc_vlayoutAlign(_theWhat):
	pass
	var newString:String = "Top"
	if _theWhat != null:
		match _theWhat:
			"MIN":
				newString = "Top"
			"MAX":
				newString = "Bottom"
			"CENTER":
				newString = "Center"
	return newString

func set_anchor_horizontal_fup(horizontalAnchor:String,theNode)->void:
	var my_width = theNode.size.x
	var myHpos = theNode.position.x
	match horizontalAnchor:
		"Left":
			theNode.anchor_left = 0.0
			theNode.anchor_right = 0.0
			theNode.position.x = myHpos
			theNode.size.x = my_width
		"Center":
			theNode.anchor_left = 0.5
			theNode.anchor_right = 0.5
			theNode.position.x = myHpos
			theNode.size.x = my_width
		"Right":
			theNode.anchor_left = 1.0
			theNode.anchor_right = 1.0
			theNode.position.x = myHpos
			theNode.size.x = my_width
		"Left and Right":
			theNode.anchor_left = 0.0
			theNode.anchor_right = 1.0
			theNode.position.x = myHpos
			theNode.size.x = my_width
			theNode.grow_horizontal = Control.GROW_DIRECTION_BOTH
		"Scale":
			pass
			#need object bounds
			
func set_anchor_vertical_fup(verticalAnchor:String,theNode)->void:
	var my_height = theNode.size.y
	var myVpos = theNode.position.y
	match verticalAnchor:
		"Top":
			theNode.anchor_top = 0.0
			theNode.anchor_bottom = 0.0
			theNode.position.y = myVpos
			theNode.size.y = my_height
		"Center":
			theNode.anchor_top = 0.5
			theNode.anchor_bottom = 0.5
			theNode.position.y = myVpos
			theNode.size.y = my_height
		"Bottom":
			theNode.anchor_top = 1.0
			theNode.anchor_bottom = 1.0
			theNode.position.y = myVpos
			theNode.size.y = my_height
		"Top and Bottom":
			theNode.anchor_top = 0.0
			theNode.anchor_bottom = 1.0
			theNode.position.y = myVpos
			theNode.size.y = my_height
			theNode.grow_vertical = Control.GROW_DIRECTION_BOTH
		"Scale":
			pass
			#need object bounds
