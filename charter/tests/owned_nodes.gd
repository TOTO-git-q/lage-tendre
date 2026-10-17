extends RefCounted
## Tests create reusable controls before adding them to a scene. Some tool tabs
## remain detached at exit. Free only orphan roots created by this test process;
## preserve everything present before the fixture was constructed.
static func snapshot() -> Array:
	return Array(Node.get_orphan_node_ids())

static func release_since(before: Array) -> void:
	for id in Node.get_orphan_node_ids():
		if id in before or not is_instance_id_valid(id): continue
		var node = instance_from_id(id)
		if node is Node and node.get_parent() == null: node.free()
