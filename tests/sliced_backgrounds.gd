extends SceneTree

const Slices = preload("../figma_slice_background.gd")
var failed:bool = false

func _initialize() -> void:
	var folder = "user://figma-slices-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var xs:Array[float] = [0.0, 8.4, 21.6, 30.5]
	var ys:Array[float] = [0.0, 7.2, 20.4, 28.2]
	var nodes:Dictionary = {}
	var ids:Array = []
	for row in 3:
		for column in 3:
			var id:String = "tile_%d_%d" % [row, column]
			var width:float = xs[column + 1] - xs[column]
			var height:float = ys[row + 1] - ys[row]
			ids.append(id)
			nodes[id] = {
				"type": "RECTANGLE", "width": width, "height": height,
				"relativeTransform": [[1.0, 0.0, xs[column]], [0.0, 1.0, ys[row]]],
				"fills": [{"type": "IMAGE", "imageHash": id}]
			}
			var image = Image.create(ceili(width), ceili(height), false, Image.FORMAT_RGBA8)
			image.fill(Color(0.2, 0.4, 0.6, 1.0))
			# Model the transparent fringe produced by independent fractional PNG exports.
			for y in image.get_height():
				for x in image.get_width():
					if (column > 0 and x == 0) or (column < 2 and x == image.get_width() - 1) or (row > 0 and y == 0) or (row < 2 and y == image.get_height() - 1):
						image.set_pixel(x, y, Color(0.2, 0.4, 0.6, 0.25))
			if row == 0 and column == 0:
				image.set_pixel(0, 0, Color.TRANSPARENT)
			image.save_png(folder.path_join(id + ".png"))
	var parent = {"width": xs[-1], "height": ys[-1], "children": ids, "fills": []}
	var result = Slices.compose(parent, nodes, folder)
	expect(not result.is_empty(), "A valid grid must merge")
	if not result.is_empty():
		var image:Image = result.texture.get_image()
		expect(image.get_size() == Vector2i(31, 28), "Composite must use shared rounded boundaries")
		for y in range(1, image.get_height() - 1):
			for x in range(1, image.get_width() - 1):
				expect(image.get_pixel(x, y).a > 0.99, "Transparent internal seam at %s" % Vector2i(x, y))
		expect(image.get_pixel(0, 0).a < 0.3, "The transparent outer corner must survive")
		expect(result.children.size() == 9, "All nine source slices must be recorded")
	var horizontal_parent = {"width": xs[-1], "height": ys[1], "children": ids.slice(0, 3), "fills": []}
	var horizontal = Slices.compose(horizontal_parent, nodes, folder)
	expect(not horizontal.is_empty() and horizontal.children.size() == 3, "Three-part button backgrounds must merge")
	var vertical_parent = {"width": xs[1], "height": ys[-1], "children": [ids[0], ids[3], ids[6]], "fills": []}
	expect(not Slices.compose(vertical_parent, nodes, folder).is_empty(), "Vertical three-part backgrounds must merge")
	var changed:Dictionary = nodes.duplicate(true)
	changed[ids[0]]["type"] = "TEXT"
	expect(Slices.grid_cells(parent, changed).is_empty(), "Never flatten text or semantic controls")
	changed = nodes.duplicate(true)
	changed[ids[0]]["width"] -= 0.5
	expect(Slices.grid_cells(parent, changed).is_empty(), "Intentional gaps must not be merged")
	changed = nodes.duplicate(true)
	changed[ids[0]]["width"] += 0.5
	expect(Slices.grid_cells(parent, changed).is_empty(), "Overlapping rectangles must not be merged")
	changed = nodes.duplicate(true)
	changed[ids[0]]["opacity"] = 0.5
	expect(Slices.grid_cells(parent, changed).is_empty(), "Translucent overlays must remain independent")
	changed = nodes.duplicate(true)
	changed[ids[0]]["fills"][0]["imageHash"] = "missing"
	expect(Slices.compose(parent, changed, folder).is_empty(), "A missing tile must fall back without dropping children")
	var translucent = Image.create(5, 5, false, Image.FORMAT_RGBA8)
	translucent.fill(Color(0.2, 0.4, 0.6, 0.5))
	Slices.repair_internal_edges(translucent, 1, 1)
	expect(absf(translucent.get_pixel(0, 0).a - 0.5) < 0.01, "Intentional transparency must not be filled")
	# The avatar window artwork has 248-253/255 alpha in otherwise solid areas.
	# Its fractional export fringe must be repaired without making it opaque.
	for alpha in [248.0 / 255.0, 252.0 / 255.0]:
		for id in ids:
			var image = Image.load_from_file(folder.path_join(id + ".png"))
			for y in image.get_height():
				for x in image.get_width():
					var pixel = image.get_pixel(x, y)
					if pixel.a > 0.9:
						pixel.a = alpha
					image.set_pixel(x, y, pixel)
			image.save_png(folder.path_join(id + ".png"))
		var almost_opaque = Slices.compose(parent, nodes, folder)
		expect(not almost_opaque.is_empty(), "Almost-opaque backgrounds must merge")
		if not almost_opaque.is_empty():
			var image:Image = almost_opaque.texture.get_image()
			var interior_alpha = image.get_pixel(3, 3).a
			for y in range(1, image.get_height() - 1):
				for x in range(1, image.get_width() - 1):
					expect(absf(image.get_pixel(x, y).a - interior_alpha) < 0.01, "Almost-opaque seam at %s" % Vector2i(x, y))
			expect(interior_alpha < 0.99, "Do not force artwork opaque")
			expect(image.get_pixel(0, 0).a < 0.3, "Almost-opaque artwork must keep its transparent corner")
	if not failed:
		print("FIGMA_SLICED_BACKGROUNDS_OK")
	quit(1 if failed else 0)

func expect(condition:bool, message:String) -> void:
	if not condition:
		failed = true
		push_error(message)
