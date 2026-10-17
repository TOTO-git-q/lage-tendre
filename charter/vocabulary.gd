extends RefCounted
const PATH = "res://camera_vocab.json"
static var cached: Dictionary={}
static func data() -> Dictionary:
	if cached.is_empty(): cached=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return cached
static func value(channel: String, word):
	var d = data().get(channel,{})
	if d.is_empty(): return null
	if word is float or word is int:
		return float(word) if float(word)>=d.range[0] and float(word)<=d.range[1] else null
	for level in d.levels:
		if level.word == word: return float(level.value)
	return null
static func describe(channel: String, n: float) -> Dictionary:
	var d = data()[channel]; var best = d.levels[0]
	for l in d.levels:
		if absf(l.value-n)<absf(best.value-n): best=l
	return {"value":n,"word":best.word,"unit":d.unit,"meaning":d.meaning}
