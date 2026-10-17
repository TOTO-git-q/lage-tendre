extends SceneTree
## Live status only. Login and logout are exclusively user initiated.
var received=false
func _init() -> void: run.call_deferred()
func run() -> void:
	var bridge=preload("res://claude_bridge.gd").new(); root.add_child(bridge)
	bridge.auth_state.connect(func(value):
		received=true
		assert(value.has("loggedIn") or value.has("error"))
		assert(not value.has("accessToken") and not value.has("refreshToken"))
		print("AUTH_STATUS ","unavailable" if value.has("error") else ("logged in" if value.loggedIn else "logged out")))
	var result=bridge.auth("status")
	assert(result.has("started") or result.has("error"))
	var deadline=Time.get_ticks_msec()+15000
	while not received and Time.get_ticks_msec()<deadline: await process_frame
	print("CHARTER_AUTH ","PASS" if received else "FAIL timeout")
	bridge.queue_free(); await process_frame
	quit(0 if received else 1)
