extends RefCounted
## Conversation-local copies. ZIP central-directory limits are checked BEFORE ZIPReader allocates.
const MAX_FILE = 300 * 1024 * 1024
const MAX_FILES = 20
const MAX_ENTRY = 64 * 1024 * 1024
const MAX_TOTAL = 512 * 1024 * 1024
var conversation_id = ""
var items: Array = []

func folder() -> String:
	return "user://charter_attachments/" + conversation_id

func start(id: String = "") -> void:
	conversation_id = id if id.is_valid_identifier() else "c_" + Crypto.new().generate_random_bytes(16).hex_encode()
	items = []
	var manifest = folder().path_join("manifest.json")
	if FileAccess.file_exists(manifest):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if saved is Array:
			for row in saved:
				if row is Dictionary and str(row.get("id", "")).is_valid_identifier() and FileAccess.file_exists(path(row)): items.append(row)

func persist() -> void:
	DirAccess.make_dir_recursive_absolute(folder())
	var f = FileAccess.open(folder().path_join("manifest.json"), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(items))

func path(row: Dictionary) -> String:
	return folder().path_join(str(row.id))

func find(id: String) -> Dictionary:
	for row in items:
		if row.id == id: return row
	return {}

static func kind(name: String) -> String:
	var ext = name.get_extension().to_lower()
	if ext in ["osz", "osu", "zip", "json"]: return ext
	if ext in ["txt", "md", "csv", "gd", "log"]: return "text"
	if ext in ["png", "jpg", "jpeg", "webp"]: return "image"
	if ext in ["wav", "ogg", "mp3"]: return "audio"
	return "other"

func attach(source: String) -> Dictionary:
	if conversation_id.is_empty(): start()
	if items.size() >= MAX_FILES: return {"error": "每个对话最多 20 个附件，请先移除附件"}
	if not FileAccess.file_exists(source) or DirAccess.open(source.get_base_dir()).is_link(source.get_file()): return {"error": "只能添加普通文件，不能添加文件夹或链接"}
	var input = FileAccess.open(source, FileAccess.READ)
	if not input: return {"error": "无法读取附件"}
	var size = input.get_length()
	if size > MAX_FILE: return {"error": "每个附件不能超过 300 MB"}
	var row = {"id": "a_" + Crypto.new().generate_random_bytes(12).hex_encode(), "name": source.get_file(), "bytes": size, "kind": kind(source), "sha256": ""}
	DirAccess.make_dir_recursive_absolute(folder())
	var output = FileAccess.open(path(row), FileAccess.WRITE)
	if not output: return {"error": "无法复制附件"}
	while input.get_position() < size:
		output.store_buffer(input.get_buffer(mini(1024 * 1024, size - input.get_position())))
	output.close(); input.close()
	row.sha256 = FileAccess.get_sha256(path(row)); items.append(row); persist()
	return row.duplicate()

func remove(id: String) -> void:
	var row = find(id)
	if row.is_empty(): return
	DirAccess.remove_absolute(path(row)); items.erase(row); persist()

func delete_conversation() -> void:
	for row in items: DirAccess.remove_absolute(path(row))
	DirAccess.remove_absolute(folder().path_join("manifest.json")); DirAccess.remove_absolute(folder()); items = []

static func safe_entry(name: String) -> bool:
	if name.is_empty() or name.is_absolute_path() or ":" in name or "\\" in name or 0 in name.to_utf8_buffer(): return false
	for part in name.split("/"):
		if part in ["..", "."]: return false
	return true

func entries(id: String) -> Dictionary:
	var row = find(id)
	if row.is_empty(): return {"error": "unknown attachment"}
	if not row.kind in ["zip", "osz"]: return {"error": "attachment is not a ZIP/OSZ"}
	var f = FileAccess.open(path(row), FileAccess.READ)
	var length = f.get_length()
	if length < 22: return {"error": "invalid ZIP"}
	# Locate EOCD, rejecting multi-disk and ZIP64 (not needed for the bounded input).
	f.seek(maxi(0, length - 65557)); var tail = f.get_buffer(mini(length, 65557)); var end = -1
	for i in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50 and i + 22 + tail.decode_u16(i + 20) == tail.size(): end = i; break
	if end < 0: return {"error": "invalid ZIP directory"}
	var count = tail.decode_u16(end + 10); var start_at = tail.decode_u32(end + 16); var directory_size = tail.decode_u32(end + 12)
	if tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0 or tail.decode_u16(end + 8) != count or count > 2048 or start_at + directory_size > length - 22: return {"error": "ZIP directory limits exceeded"}
	f.seek(start_at); var rows = []; var total = 0; var seen = {}
	for i in count:
		var h = f.get_buffer(46)
		if h.size() != 46 or h.decode_u32(0) != 0x02014b50: return {"error": "invalid ZIP entry"}
		var compressed = h.decode_u32(20); var size = h.decode_u32(24); var name_len = h.decode_u16(28); var extra = h.decode_u16(30); var comment = h.decode_u16(32)
		var name = f.get_buffer(name_len).get_string_from_utf8(); total += size
		if not safe_entry(name) or seen.has(name.to_lower()): return {"error": "unsafe or duplicate ZIP path"}
		if h.decode_u16(8) & 1 or h.decode_u16(10) not in [0, 8] or h.decode_u32(42) >= start_at or size > MAX_ENTRY or total > MAX_TOTAL or size > maxi(1024 * 1024, compressed * 200): return {"error": "ZIP entry size/compression limits exceeded"}
		seen[name.to_lower()] = true; rows.append({"entry": name, "bytes": size}); f.seek(f.get_position() + extra + comment)
	if f.get_position() != start_at + directory_size: return {"error": "invalid ZIP directory size"}
	return {"entries": rows, "total_bytes": total}

func data(id: String, entry: String = "", cap: int = MAX_ENTRY) -> Dictionary:
	var row = find(id)
	if row.is_empty(): return {"error": "unknown attachment"}
	if row.kind in ["zip", "osz"]:
		var listing = entries(id)
		if listing.has("error"): return listing
		var found = false
		for e in listing.entries:
			if e.entry == entry:
				if e.bytes > cap: return {"error": "entry exceeds content limit"}
				found = true
		if not found or entry.ends_with("/"): return {"error": "entry not found"}
		var zip = ZIPReader.new()
		if zip.open(path(row)) != OK: return {"error": "cannot open ZIP"}
		var bytes = zip.read_file(entry); zip.close()
		return {"data": bytes}
	if not entry.is_empty(): return {"error": "entry is only valid for ZIP/OSZ"}
	if row.bytes > cap: return {"error": "file exceeds content limit"}
	return {"data": FileAccess.get_file_as_bytes(path(row))}

func read(a: Dictionary) -> Dictionary:
	var row = find(str(a.get("id", "")))
	if row.is_empty(): return {"error": "unknown attachment"}
	if row.kind in ["zip", "osz"] and str(a.get("entry", "")).is_empty(): return entries(row.id)
	var offset = maxi(0, int(a.get("offset", 0))); var limit = clampi(int(a.get("limit", 16384)), 1, 65536)
	if row.kind not in ["zip","osz"]:
		if not str(a.get("entry","")).is_empty(): return {"error":"entry is only valid for ZIP/OSZ"}
		var f = FileAccess.open(path(row),FileAccess.READ)
		if not f: return {"error":"cannot open attachment"}
		var total = f.get_length()
		if offset > total: return {"error":"offset exceeds file size"}
		f.seek(offset); var page = f.get_buffer(mini(limit+4,total-offset))
		if not page.is_empty() and page[0] & 0xc0 == 0x80: return {"error":"offset must be a UTF-8 byte boundary"}
		var end = mini(limit,page.size())
		while end < page.size() and end > 0 and page[end] & 0xc0 == 0x80: end -= 1
		if end == 0 and offset < total: return {"error":"limit is too small for one UTF-8 codepoint"}
		page = page.slice(0,end); var text = page.get_string_from_utf8()
		if text.to_utf8_buffer() != page or 0 in page: return {"error":"content is not UTF-8 text"}
		return {"text":text,"offset":offset,"next_offset":offset+end,"total_bytes":total,"done":offset+end == total,"untrusted":true}
	var result = data(row.id, str(a.get("entry", "")))
	if result.has("error"): return result
	var bytes: PackedByteArray = result.data
	var text = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes or 0 in bytes: return {"error": "content is not UTF-8 text"}
	# Byte offsets, cut at complete UTF-8 codepoints.
	if offset > bytes.size() or (offset < bytes.size() and bytes[offset] & 0xc0 == 0x80): return {"error": "offset must be a UTF-8 byte boundary"}
	var stop = mini(bytes.size(), offset + limit)
	while stop < bytes.size() and stop > offset and bytes[stop] & 0xc0 == 0x80: stop -= 1
	if stop == offset and offset < bytes.size(): return {"error":"limit is too small for one UTF-8 codepoint"}
	return {"text": bytes.slice(offset, stop).get_string_from_utf8(), "offset": offset, "next_offset": stop, "total_bytes": bytes.size(), "done": stop == bytes.size(), "untrusted": true}

func image_content(a: Dictionary) -> Dictionary:
	var result = data(str(a.get("id", "")), str(a.get("entry", "")), 8 * 1024 * 1024)
	if result.has("error"): return result
	var bytes: PackedByteArray = result.data
	var image = Image.new(); var err = ERR_FILE_UNRECOGNIZED
	# PNG dimensions are checked before decoding to avoid tiny compressed image bombs.
	if bytes.size() >= 24 and bytes.slice(0, 8).hex_encode() == "89504e470d0a1a0a":
		var w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19]
		var h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23]
		if w <= 0 or h <= 0 or w > 16000000 or h > 16000000 or w * h > 16000000: return {"error": "image dimensions exceed limit"}
		err = image.load_png_from_buffer(bytes)
	elif bytes.size() > 4 and bytes[0] == 255 and bytes[1] == 216:
		# Scan JPEG SOF before allocating pixels.
		var p = 2; var bounded = false
		while p + 9 < bytes.size():
			if bytes[p] != 255: break
			var marker = bytes[p + 1]; p += 2
			if marker in [0xd8, 0xd9]: continue
			var size = (bytes[p] << 8) | bytes[p + 1]
			if size < 2: break
			if marker in [0xc0, 0xc1, 0xc2]:
				var h = (bytes[p + 3] << 8) | bytes[p + 4]; var w = (bytes[p + 5] << 8) | bytes[p + 6]
				bounded = w > 0 and h > 0 and w * h <= 16000000; break
			p += size
		if not bounded: return {"error": "unsupported JPEG or image dimensions exceed limit"}
		err = image.load_jpg_from_buffer(bytes)
	if err != OK: return {"error": "expected PNG or JPEG"}
	var side = clampi(int(a.get("max_side", 1024)), 32, 1024)
	if maxi(image.get_width(), image.get_height()) > side:
		var scale = float(side) / maxi(image.get_width(), image.get_height()); image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)))
	return {"_mcp_content": [{"type": "image", "mimeType": "image/png", "data": Marshalls.raw_to_base64(image.save_png_to_buffer())}]}
