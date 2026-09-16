extends SceneTree

# Optional integration check: -- <figma_export.json> <images_folder> <fonts_folder>
var failed:bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var importer = load("res://addons/figma_importer/figma_importer.gd").new()
	root.add_child(importer)
	importer.images_folder = "res://addons/figma_importer"
	var expected:Dictionary = {}
	for mode in ["FILL", "FIT", "TILE", "CROP"]:
		for factor in [0.5, 1.0, 2.0]:
			var panel = DesignerImagePanel.new()
			panel.name = "%s_%s" % [mode, str(factor).replace(".", "_")]
			importer.add_child(panel)
			panel.owner = importer
			panel.size = Vector2(56, 56)
			var paint = {
				"type": "IMAGE", "visible": true, "imageHash": "error_texture",
				"scaleMode": mode, "scalingFactor": factor,
				"imageTransform": [[0.681818, 0.0, 0.113636], [0.0, 0.638298, 0.170213]]
			}
			var hidden_paint:Dictionary = paint.duplicate(true)
			hidden_paint["visible"] = false
			hidden_paint["scaleMode"] = "TILE"
			importer.process_colors([paint, hidden_paint], panel)
			expected[importer.get_path_to(panel)] = {
				"mode": "Keep Size" if mode == "TILE" else ("Fit" if mode == "FIT" else "Fill"),
				"zoom": factor if mode == "TILE" else 1.0,
				"texture": "res://addons/figma_importer/error_texture.png"
			}
	check_panels(importer, expected)
	check_saved_scene(importer, expected)
	importer.free()
	var args = OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() < 3:
			expect(false, "Pass JSON, images folder, and fonts folder after --")
		else:
			await check_export(args[0], args[1], args[2])
	if not failed:
		print("FIGMA_IMAGE_FILLS_OK")
	quit(1 if failed else 0)

func check_export(json_path:String, images_folder:String, fonts_folder:String) -> void:
	var document = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var source:Dictionary = document["children"][0]["children"][0]
	var importer = load("res://addons/figma_importer/figma_importer.gd").new()
	root.add_child(importer)
	importer.images_folder = images_folder
	importer.fonts_folder = fonts_folder
	importer.cycle_children(document["children"], document["id"])
	importer.renderFrameAndContents(source["id"], importer, true)
	for i in 3:
		await process_frame
	var expected:Dictionary = {}
	for node in importer.find_children("*", "", true, false):
		if not (node is DesignerImagePanel or node is DesignerFrame) or node.has_meta("figma_slice_children"):
			continue
		var data:Dictionary = importer.processed_json_dict[node.the_id]
		var paints = data.get("fills")
		if not paints is Array:
			continue
		for paint in paints:
			if paint.get("type") == "IMAGE" and paint.get("visible", true) and paint.get("scaleMode") == "CROP":
				expected[importer.get_path_to(node)] = {
					"mode": "Fill", "zoom": 1.0,
					"texture": images_folder.path_join(paint["imageHash"] + ".png")
				}
	expect(not expected.is_empty(), "The export must exercise cropped images")
	check_panels(importer, expected)
	check_saved_scene(importer, expected)
	print("FIGMA_CROPPED_IMAGES_CHECKED: ", expected.size())
	importer.free()

func check_saved_scene(importer:Node, expected:Dictionary) -> void:
	var path = "user://figma-image-fills-%s.tscn" % Time.get_ticks_usec()
	var packed = PackedScene.new()
	expect(packed.pack(importer) == OK, "Could not pack image fill scene")
	expect(ResourceSaver.save(packed, path) == OK, "Could not save image fill scene")
	var saved = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	expect(saved != null, "Could not reload image fill scene")
	if saved != null:
		var instance = saved.instantiate()
		root.add_child(instance)
		check_panels(instance, expected)
		instance.free()
	DirAccess.remove_absolute(path)

func check_panels(importer:Node, expected:Dictionary) -> void:
	for path in expected:
		var panel = importer.get_node(path)
		var settings:Dictionary = expected[path]
		var label = str(path)
		expect(panel.fill_texture != null and panel.fill_texture.resource_path == settings.texture, label + ": wrong image")
		expect(panel.textureSizeMode == settings.mode, label + ": incorrect texture sizing")
		expect(is_equal_approx(panel.zoom, settings.zoom), label + ": image scaled twice")
		var tiled:bool = settings.mode == "Keep Size"
		expect(panel.tile_texture == tiled, label + ": incorrect tiling")
		var material = panel.material as ShaderMaterial
		expect(material != null, label + ": missing image shader")
		if material != null:
			expect(material.get_shader_parameter("manual_scale") == tiled, label + ": incorrect shader sizing")
			expect(material.get_shader_parameter("fill_rect") == (settings.mode == "Fill"), label + ": incorrect shader fill")
			expect(is_equal_approx(material.get_shader_parameter("texture_scale"), settings.zoom), label + ": incorrect shader scale")

func expect(condition:bool, message:String) -> void:
	if not condition:
		failed = true
		push_error(message)
