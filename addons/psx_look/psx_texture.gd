class_name PSXTexture
## A texture made over as the PS1 kept one: shrunk to fit its 1 MB of video memory, and its colours
## cut to a 4-bit or 8-bit palette (a CLUT of 16 or 256 colours).
##
##     material.set_shader_parameter(&"albedo_texture", PSXTexture.shrink(texture, 64, 16))
##     PSX.convert(level, 64, 16)   # every texture of the level's materials, once each
##
## It works on the image, once, so it is best done as a level loads; a 256-pixel texture takes a
## few hundredths of a second.


## A copy of `texture` at most `size` pixels on its longer side (0 keeps its size), halved and
## filtered down so its detail averages out rather than drops out; with `colors` above 0, its
## colours cut to a palette of that many (16 and 256 were the PS1's), chosen by median cut from its
## 15-bit colours. Fully transparent pixels stay as they are.
static func shrink(texture: Texture2D, size := 128, colors := 0) -> ImageTexture:
	var img: Image = texture.get_image().duplicate()  # never the texture's own, which some renderers hand back
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if size > 0:
		while maxi(img.get_width(), img.get_height()) >= size * 2:
			img.shrink_x2()
		var longer := maxi(img.get_width(), img.get_height())
		if longer > size:
			img.resize(maxi(1, img.get_width() * size / longer), maxi(1, img.get_height() * size / longer),
					Image.INTERPOLATE_BILINEAR)
	if colors > 0:
		_palette(img, colors)
	return ImageTexture.create_from_image(img)


## Cuts `img`'s colours to at most `colors`: its 15-bit colours, counted, split by median cut along
## the widest channel of the widest box until there are that many boxes; each box becomes its
## pixels' average, kept to 15 bits as a CLUT entry was.
static func _palette(img: Image, colors: int) -> void:
	var data := img.get_data()
	var counts := {}
	for i in range(0, data.size(), 4):
		if data[i + 3] > 0:
			var key := (data[i] >> 3) << 10 | (data[i + 1] >> 3) << 5 | data[i + 2] >> 3
			counts[key] = counts.get(key, 0) + 1
	if counts.is_empty():
		return
	var boxes: Array[PackedInt32Array] = [PackedInt32Array(counts.keys())]
	var widths: Array[Vector2i] = [_widest(boxes[0])]  # each box's widest channel: its range, which
	while boxes.size() < colors:
		var b := -1
		for i in boxes.size():
			if widths[i].x > 0 and (b < 0 or widths[i].x > widths[b].x):
				b = i
		if b < 0:
			break  # fewer colours than asked for: each is its own box already
		var halves := _split(boxes[b], widths[b].y, counts)
		boxes[b] = halves[0]
		widths[b] = _widest(halves[0])
		boxes.append(halves[1])
		widths.append(_widest(halves[1]))
	var lut := {}
	var palette := PackedByteArray()
	for b in boxes.size():
		var sum := Vector3.ZERO
		var n := 0
		for key in boxes[b]:
			var k: int = counts[key]
			sum += Vector3(key >> 10, (key >> 5) & 31, key & 31) * k
			n += k
			lut[key] = b
		var mean := (sum / n).round()
		for v in [mean.x, mean.y, mean.z]:
			palette.append(int(v) * 255 / 31)
	for i in range(0, data.size(), 4):
		if data[i + 3] > 0:
			var e: int = lut[(data[i] >> 3) << 10 | (data[i + 1] >> 3) << 5 | data[i + 2] >> 3] * 3
			data[i] = palette[e]
			data[i + 1] = palette[e + 1]
			data[i + 2] = palette[e + 2]
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


static func _value(key: int, channel: int) -> int:
	return (key >> (10 - channel * 5)) & 31


## The channel `box`'s colours spread furthest along, as (its range, the channel).
static func _widest(box: PackedInt32Array) -> Vector2i:
	var lo := Vector3i(31, 31, 31)
	var hi := Vector3i.ZERO
	for key in box:
		var v := Vector3i(key >> 10, (key >> 5) & 31, key & 31)
		lo = Vector3i(mini(lo.x, v.x), mini(lo.y, v.y), mini(lo.z, v.z))
		hi = Vector3i(maxi(hi.x, v.x), maxi(hi.y, v.y), maxi(hi.z, v.z))
	var r := hi - lo
	var c := 0 if r.x >= r.y and r.x >= r.z else (1 if r.y >= r.z else 2)
	return Vector2i(r[c], c)


## `box` sorted along `channel` and cut where half its pixels lie each side, neither half empty.
static func _split(box: PackedInt32Array, channel: int, counts: Dictionary) -> Array[PackedInt32Array]:
	var order := PackedInt32Array()
	for key in box:
		order.append(_value(key, channel) << 15 | key)
	order.sort()
	var total := 0
	for key in box:
		total += counts[key]
	var at := 0
	var seen := 0
	while at < order.size() - 1:
		seen += counts[order[at] & 32767]
		at += 1
		if seen * 2 >= total:
			break
	var low := PackedInt32Array()
	var high := PackedInt32Array()
	for i in order.size():
		if i < at:
			low.append(order[i] & 32767)
		else:
			high.append(order[i] & 32767)
	return [low, high]
