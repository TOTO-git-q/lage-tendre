## Rank tiers of the result screen (CHUNITHM-like thresholds on the 0..1,010,000 score).
extends RefCounted

const TIERS := [
	{"name": "SSS", "min": 1007500},
	{"name": "SS", "min": 1000000},
	{"name": "S", "min": 975000},
	{"name": "AAA", "min": 950000},
	{"name": "AA", "min": 925000},
	{"name": "A", "min": 900000},
	{"name": "BBB", "min": 800000},
	{"name": "BB", "min": 700000},
	{"name": "B", "min": 600000},
	{"name": "F", "min": 0},
]

static func rank_of(score: int) -> String:
	for t in TIERS:
		if score >= int(t.min): return t.name
	return "F"

static func index_of(name: String) -> int:
	for i in TIERS.size():
		if TIERS[i].name == name: return i
	return TIERS.size() - 1

static func min_of(name: String) -> int:
	return int(TIERS[index_of(name)].min)

## the next tier up (empty at SSS) and the score it needs
static func next_of(name: String) -> Dictionary:
	var i := index_of(name)
	return {} if i == 0 else TIERS[i - 1]

## in-engine tint of the white emblem: SSS/SS faint gold, S/A tiers ice, B tiers neutral, F dim
static func tint_of(name: String) -> Color:
	match name:
		"SSS": return Color(1.0, 0.95, 0.80)
		"SS": return Color(1.0, 0.96, 0.85)
		"S": return Color(0.90, 0.96, 1.0)
		"AAA", "AA", "A": return Color(0.78, 0.89, 1.0)
		"BBB", "BB", "B": return Color(0.92, 0.92, 0.92)
	return Color(0.55, 0.55, 0.58)

## 0..1: how strong the glow bloom of the stamp is (the higher the tier, the brighter)
static func glow_of(name: String) -> float:
	return clampf(1.0 - index_of(name) * 0.1, 0.15, 1.0)

## fake stats for --result-demo=<RANK>
static func demo_stats(name: String) -> Dictionary:
	var total := 1200
	var score := int(min_of(name)) + (4000 if name != "F" and name != "SSS" else 1000)
	if name == "SSS": score = 1009120
	if name == "F": score = 413250
	var s := {"CRITICAL": 0, "PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0, "combo": 0, "maxCombo": 0, "total": total, "judged": total,
		"accuracy": 0.0, "accuracyLive": 0.0, "score": score, "fast": 0, "slow": 0}
	match name:
		"SSS": s.CRITICAL = 1130; s.PERFECT = 1200; s.maxCombo = 1200; s.fast = 20; s.slow = 18
		"SS": s.CRITICAL = 700; s.PERFECT = 1195; s.GREAT = 5; s.maxCombo = 612; s.fast = 31; s.slow = 24
		"S": s.CRITICAL = 640; s.PERFECT = 1130; s.GREAT = 60; s.GOOD = 8; s.MISS = 2; s.maxCombo = 480; s.fast = 40; s.slow = 70
		"AAA": s.CRITICAL = 600; s.PERFECT = 1080; s.GREAT = 90; s.GOOD = 22; s.MISS = 8; s.maxCombo = 391; s.fast = 70; s.slow = 62
		"AA": s.CRITICAL = 500; s.PERFECT = 1010; s.GREAT = 120; s.GOOD = 40; s.MISS = 30; s.maxCombo = 288; s.fast = 66; s.slow = 101
		"A": s.CRITICAL = 440; s.PERFECT = 960; s.GREAT = 150; s.GOOD = 50; s.MISS = 40; s.maxCombo = 201; s.fast = 120; s.slow = 80
		"BBB": s.CRITICAL = 300; s.PERFECT = 800; s.GREAT = 200; s.GOOD = 100; s.MISS = 100; s.maxCombo = 120; s.fast = 150; s.slow = 150
		"BB": s.CRITICAL = 220; s.PERFECT = 700; s.GREAT = 220; s.GOOD = 120; s.MISS = 160; s.maxCombo = 77; s.fast = 190; s.slow = 150
		"B": s.CRITICAL = 160; s.PERFECT = 620; s.GREAT = 250; s.GOOD = 130; s.MISS = 200; s.maxCombo = 52; s.fast = 200; s.slow = 180
		_: s.CRITICAL = 40; s.PERFECT = 330; s.GREAT = 240; s.GOOD = 180; s.MISS = 450; s.maxCombo = 19; s.fast = 230; s.slow = 210
	var credit: float = s.PERFECT + SU.CREDIT_GREAT * s.GREAT + SU.CREDIT_GOOD * s.GOOD
	s.accuracy = credit / total
	s.accuracyLive = s.accuracy
	return s
