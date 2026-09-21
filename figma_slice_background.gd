@tool
extends RefCounted

const EDGE_TOLERANCE:float = 0.02

## Recognize complete, non-overlapping 3x3, 3x1, or 1x3 image grids.
## Controls containing text, decoration, transforms, or missing images remain editable nodes.
static func grid_cells(data:Dictionary, nodes:Dictionary) -> Array:
	var children:Array = data.get("children", [])
	if children.size() not in [3, 9] or not visible_paints(data.get("fills")).is_empty():
		return []
	var xs:Array[float] = []
	var ys:Array[float] = []
	var cells:Array = []
	for id in children:
		var child:Dictionary = nodes.get(id, {})
		if child.get("type") != "RECTANGLE" or not child.get("visible", true) or not is_equal_approx(child.get("opacity", 1.0), 1.0):
			return []
		if not child.get("children", []).is_empty() or not visible_paints(child.get("border_color")).is_empty() or not visible_paints(child.get("effects")).is_empty():
			return []
		for radius in child.get("corner_radius", []):
			if radius != null and (not (radius is float or radius is int) or not is_zero_approx(float(radius))):
				return []
		var paints = visible_paints(child.get("fills"))
		if paints.size() != 1 or paints[0].get("type") != "IMAGE" or not is_equal_approx(paints[0].get("opacity", 1.0), 1.0):
			return []
		if child.get("blendMode", "NORMAL") not in ["NORMAL", "PASS_THROUGH"] or paints[0].get("blendMode", "NORMAL") != "NORMAL":
			return []
		var matrix = child.get("relativeTransform")
		if not matrix is Array or matrix.size() != 2 or matrix[0].size() != 3 or matrix[1].size() != 3:
			return []
		if not is_equal_approx(matrix[0][0], 1.0) or not is_equal_approx(matrix[1][1], 1.0) or not is_zero_approx(matrix[0][1]) or not is_zero_approx(matrix[1][0]):
			return []
		var rect = Rect2(matrix[0][2], matrix[1][2], child.get("width", 0.0), child.get("height", 0.0))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return []
		add_edge(xs, rect.position.x)
		add_edge(ys, rect.position.y)
		cells.append({"id": id, "rect": rect, "hash": paints[0].get("imageHash", "")})
	var columns:int = xs.size()
	var rows:int = ys.size()
	if columns not in [1, 3] or rows not in [1, 3] or columns * rows != children.size():
		return []
	xs.sort()
	ys.sort()
	if absf(xs[0]) > EDGE_TOLERANCE or absf(ys[0]) > EDGE_TOLERANCE:
		return []
	xs[0] = 0.0
	ys[0] = 0.0
	xs.append(data["width"])
	ys.append(data["height"])
	var occupied:Dictionary = {}
	for cell in cells:
		var rect:Rect2 = cell.rect
		var column = edge_index(xs, rect.position.x)
		var row = edge_index(ys, rect.position.y)
		if column < 0 or column >= columns or row < 0 or row >= rows or occupied.has(Vector2i(column, row)):
			return []
		if absf(rect.end.x - xs[column + 1]) > EDGE_TOLERANCE or absf(rect.end.y - ys[row + 1]) > EDGE_TOLERANCE:
			return []
		occupied[Vector2i(column, row)] = true
		# Round shared edges, never each tile's width independently.
		var start = Vector2i(roundi(xs[column]), roundi(ys[row]))
		var end = Vector2i(roundi(xs[column + 1]), roundi(ys[row + 1]))
		if end.x <= start.x or end.y <= start.y:
			return []
		cell["pixels"] = Rect2i(start, end - start)
		cell["column"] = column
		cell["row"] = row
		cell["columns"] = columns
		cell["rows"] = rows
	return cells

static func compose(data:Dictionary, nodes:Dictionary, images_folder:String) -> Dictionary:
	var cells = grid_cells(data, nodes)
	if cells.is_empty() or images_folder.is_empty():
		return {}
	var width:int = roundi(data["width"])
	var height:int = roundi(data["height"])
	if width <= 0 or height <= 0 or width * height > 16777216:
		return {}
	var slices:Array[Image] = []
	for cell in cells:
		var hash:String = cell.hash
		if hash.is_empty() or hash.contains("/") or hash.contains("\\") or hash.contains(":"):
			return {}
		var path = images_folder.path_join(hash + ".png")
		# These PNGs are already cropped/rasterized by the Figma exporter.
		var image:Image
		if path.begins_with("res://"):
			if not ResourceLoader.exists(path):
				return {}
			var texture = load(path) as Texture2D
			if texture == null:
				return {}
			image = texture.get_image()
		else:
			if not FileAccess.file_exists(path):
				return {}
			image = Image.load_from_file(path)
		if image == null or image.is_empty():
			return {}
		if image.is_compressed() and image.decompress() != OK:
			return {}
		image.convert(Image.FORMAT_RGBA8)
		repair_internal_edges(image, cell.column, cell.row, cell.columns, cell.rows)
		var pixels:Rect2i = cell.pixels
		image.resize(pixels.size.x, pixels.size.y, Image.INTERPOLATE_BILINEAR)
		slices.append(image)
	var composite = Image.create(width, height, false, Image.FORMAT_RGBA8)
	composite.fill(Color.TRANSPARENT)
	var ids:PackedStringArray = []
	for index in cells.size():
		var tile = slices[index]
		composite.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), cells[index].pixels.position)
		ids.append(cells[index].id)
	return {"texture": ImageTexture.create_from_image(composite), "children": ids}

static func visible_paints(value) -> Array:
	var result:Array = []
	if value is Array:
		for item in value:
			if item is Dictionary and item.get("visible", true):
				result.append(item)
	return result

static func add_edge(edges:Array[float], value:float) -> void:
	if edge_index(edges, value) < 0:
		edges.append(value)

static func edge_index(edges:Array[float], value:float) -> int:
	for index in edges.size():
		if absf(edges[index] - value) <= EDGE_TOLERANCE:
			return index
	return -1

static func repair_internal_edges(image:Image, column:int, row:int, columns:int = 3, rows:int = 3) -> void:
	# Fractional PNG export bounds can leave a partially transparent outer pixel.
	# Extend opaque neighboring pixels at internal joins only. Preserve transparent
	# corners and the outer silhouette; never force the whole image opaque.
	var width = image.get_width()
	var height = image.get_height()
	if width > 1:
		for y in height:
			if column > 0:
				repair_pixel(image, Vector2i(0, y), Vector2i(1, y))
			if column < columns - 1:
				repair_pixel(image, Vector2i(width - 1, y), Vector2i(width - 2, y))
	if height > 1:
		for x in width:
			if row > 0:
				repair_pixel(image, Vector2i(x, 0), Vector2i(x, 1))
			if row < rows - 1:
				repair_pixel(image, Vector2i(x, height - 1), Vector2i(x, height - 2))

static func repair_pixel(image:Image, edge:Vector2i, neighbor:Vector2i) -> void:
	var inside = image.get_pixelv(neighbor)
	# Exported artwork can be almost opaque (e.g. 252/255), including its
	# interior. Keep that alpha when extending it into the clipped edge.
	if inside.a >= 0.95 and image.get_pixelv(edge).a < inside.a - 0.01:
		image.set_pixelv(edge, inside)
