extends SceneTree
## godot --headless --path . --script tests/ranks_test.gd
func _init() -> void:
	var cases := {1010000: "SSS", 1007500: "SSS", 1007499: "SS", 1000000: "SS", 999999: "S", 975000: "S", 974999: "AAA", 950000: "AAA", 949999: "AA",
		925000: "AA", 924999: "A", 900000: "A", 899999: "BBB", 800000: "BBB", 799999: "BB", 700000: "BB", 699999: "B", 600000: "B", 599999: "F", 0: "F"}
	var bad := 0
	for sc in cases:
		var r := Ranks.rank_of(sc)
		if r != cases[sc]: bad += 1; print("FAIL ", sc, " -> ", r, " want ", cases[sc])
	for t in Ranks.TIERS:
		var st := Ranks.demo_stats(t.name)
		if Ranks.rank_of(int(st.score)) != t.name: bad += 1; print("FAIL demo ", t.name, " score ", st.score)
	print("ranks_test: ", "OK" if bad == 0 else "%d failures" % bad)
	quit(1 if bad else 0)
