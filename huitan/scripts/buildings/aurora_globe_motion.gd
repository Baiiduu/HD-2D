extends AnimationPlayer
## Engine animation updates a single material phase; no scripted frame callback.

func _ready() -> void:
	_bind_session.call_deferred()

func _bind_session() -> void:
	var ancestor := get_parent()
	while ancestor:
		var session := ancestor.get_node_or_null("WavePrototype") as WavePrototype
		if session:
			session.register_combat_node(self)
			return
		ancestor = ancestor.get_parent()
