extends SceneTree

var failed:bool = false
var imported_by_id:Dictionary = {}

func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 1:
		root.hide()
	_run.call_deferred()

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the Figma JSON path after --")
		quit(1)
		return
	var document = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var source:Dictionary = document["children"][0]["children"][0]
	var importer = load("res://addons/figma_importer/figma_importer.gd").new()
	var surface = SubViewport.new()
	surface.size = Vector2i(source["width"], source["height"])
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	surface.add_child(importer)
	importer.size = Vector2(source["width"], source["height"])
	importer.fonts_folder = args[0].get_base_dir().path_join("fonts")
	importer.images_folder = args[0].get_base_dir().path_join("images")
	importer.cycle_children(document["children"], document["id"])
	importer.renderFrameAndContents(source["id"], importer, true)
	for i in 12:
		await process_frame
	collect(importer)
	var expected_count = count_nodes(source)
	expect(imported_by_id.size() == expected_count, "Node count: expected %d, got %d" % [expected_count, imported_by_id.size()])
	var root_transform = load("res://addons/figma_importer/figma_gradient.gd").transform_from_array(source["absoluteTransform"])
	check_layout(source, root_transform.affine_inverse())
	# The result must survive scene serialization, including fonts and gradient materials.
	var packed = PackedScene.new()
	expect(packed.pack(importer) == OK, "Could not pack the imported scene")
	expect(ResourceSaver.save(packed, "user://figma-render-regression.tscn") == OK, "Could not save the imported scene")
	importer.free()
	imported_by_id.clear()
	var saved:PackedScene = ResourceLoader.load("user://figma-render-regression.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	importer = saved.instantiate()
	surface.add_child(importer)
	for i in 12:
		await process_frame
	collect(importer)
	expect(imported_by_id.size() == expected_count, "Node count changed after scene reload")
	check_layout(source, root_transform.affine_inverse())
	if args.size() > 1:
		if args.size() > 2:
			var preview_scale:float = float(args[2])
			importer.scale = Vector2.ONE * preview_scale
			surface.size = Vector2i(roundi(source["width"] * preview_scale), roundi(source["height"] * preview_scale))
			await process_frame
		await RenderingServer.frame_post_draw
		var preview = surface.get_texture().get_image()
		expect(preview.save_png(args[1]) == OK, "Could not save render preview")
	print("FIGMA_RENDER_CHECKED: ", imported_by_id.size(), " nodes")
	var merged_count:int = 0
	for control in imported_by_id.values():
		if control.has_meta("figma_slice_children"):
			merged_count += 1
	print("FIGMA_MERGED_BACKGROUNDS: ", merged_count)
	if not failed:
		print("FIGMA_RENDER_LAYOUT_OK")
	importer.free()
	quit(1 if failed else 0)

func collect(node:Node) -> void:
	if node is Control:
		var name_text = str(node.name)
		var marker = name_text.find("xIDx")
		if marker >= 0:
			var id = name_text.substr(marker + 4).trim_suffix("x").replace("_", ":")
			imported_by_id[id] = node
	for child in node.get_children():
		collect(child)

func count_nodes(node:Dictionary) -> int:
	var result:int = 1
	if imported_by_id.has(node["id"]) and imported_by_id[node["id"]].has_meta("figma_slice_children"):
		return result
	for child in node.get("children", []):
		result += count_nodes(child)
	return result

func expect(condition:bool, message:String) -> void:
	if not condition:
		failed = true
		push_error(message)

func check_layout(node:Dictionary, root_inverse:Transform2D) -> void:
	if not imported_by_id.has(node["id"]):
		expect(false, "Missing node: " + node["id"])
	else:
		var control:Control = imported_by_id[node["id"]]
		var expected:Transform2D = root_inverse * load("res://addons/figma_importer/figma_gradient.gd").transform_from_array(node["absoluteTransform"])
		var actual = control.get_global_transform()
		var size_expected = Vector2(node["width"], node["height"])
		if node["type"] == "TEXT" and not node.get("characters", "").is_empty():
			expect(control.get_visible_line_count() >= 1, "Text has no visible lines: " + node["id"])
			if node.get("fills", []).any(func(paint): return paint.get("type") == "GRADIENT_LINEAR" and paint.get("visible", true)):
				expect(control.material is ShaderMaterial, "Text gradient material missing: " + node["id"])
		if node["type"] in ["VECTOR", "BOOLEAN_OPERATION"]:
			expect(control.fill_texture is ImageTexture, "Vector must use its exported geometry: " + node["id"])
		if control.has_meta("figma_slice_children"):
			var source_ids:PackedStringArray = []
			for child in node.get("children", []):
				source_ids.append(child["id"])
			expect(control.get_meta("figma_slice_children") == source_ids, "Merged background lost a source slice")
			expect(control.fill_texture is ImageTexture, "Merged background texture was not saved")
			expect(control.get_child_count() == 0, "Merged background still contains separate slice controls")
		if node.get("itemReverseZIndex", false) and node.get("children", []).size() >= 2:
			var first:Control = imported_by_id[node["children"][0]["id"]]
			var last:Control = imported_by_id[node["children"][-1]["id"]]
			expect(first.get_index() > last.get_index(), "Reverse stacking order was lost: " + node["id"])
		expect(actual.origin.distance_to(expected.origin) < 1.0, "%s %s position: expected %s, got %s" % [node["id"], node["name"], expected.origin, actual.origin])
		expect(actual.x.distance_to(expected.x) < 0.001 and actual.y.distance_to(expected.y) < 0.001, "%s transform: expected %s, got %s" % [node["id"], expected, actual])
		expect(control.size.distance_to(size_expected) < 1.0, "%s size: expected %s, got %s" % [node["id"], size_expected, control.size])
	if imported_by_id.has(node["id"]) and imported_by_id[node["id"]].has_meta("figma_slice_children"):
		return
	for child in node.get("children", []):
		check_layout(child, root_inverse)
