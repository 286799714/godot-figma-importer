extends SceneTree

var failed:bool = false

func _initialize() -> void:
	var importer = load("res://addons/figma_importer/figma_importer.gd").new()
	var fixture = [{
		"id": "page", "type": "PAGE", "name": "Page",
		"children": [
			{"id": "frame", "type": "FRAME", "name": "Frame", "children": [
				{"id": "missing", "type": "RECTANGLE", "name": "Missing"},
				{"id": "null", "type": "RECTANGLE", "name": "Null", "parent": null},
				{"id": "empty", "type": "RECTANGLE", "name": "Empty", "parent": {}},
				{"id": "explicit", "type": "RECTANGLE", "name": "Explicit", "parent": {"id": "preserved"}}
			]}
		]
	}]
	importer.cycle_children(fixture, "document")
	expect(importer.processed_json_dict.size() == 6, "All fixture nodes must be processed")
	expect(importer.processed_json_dict["page"]["parent"] == "document", "Page must inherit document parent")
	expect(importer.processed_json_dict["frame"]["parent"] == "page", "Frame must inherit page parent")
	for id in ["missing", "null", "empty"]:
		expect(importer.processed_json_dict[id]["parent"] == "frame", "Missing/empty parent must use nesting: " + id)
	expect(importer.processed_json_dict["explicit"]["parent"] == "preserved", "Existing parent must be preserved")
	importer.free()

	# Optional: validate a real export without changing the JSON or creating scene nodes.
	for file in OS.get_cmdline_user_args():
		check_export(file)
	if not failed:
		print("FIGMA_PARENT_RELATIONSHIPS_OK")
	quit(1 if failed else 0)

func expect(condition:bool, message:String) -> void:
	if not condition:
		failed = true
		push_error(message)

func check_export(file:String) -> void:
	var document = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not document is Dictionary or not document.get("children") is Array:
		expect(false, "Invalid fixture export: " + file)
		return
	var importer = load("res://addons/figma_importer/figma_importer.gd").new()
	importer.cycle_children(document["children"], str(document.get("id", "")))
	check_children(importer, document)
	print("FIGMA_EXPORT_PROCESSED: ", importer.processed_json_dict.size(), " nodes from ", file)
	importer.free()

func check_children(importer, node:Dictionary) -> void:
	for child in node.get("children", []):
		if not importer.processed_json_dict.has(child["id"]):
			expect(false, "Unprocessed node: " + child["id"])
			continue
		expect(importer.processed_json_dict[child["id"]]["parent"] == node["id"], "Incorrect parent: " + child["id"])
		check_children(importer, child)
