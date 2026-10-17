extends "res://tests/test_ground_low_obstacles.gd"

func run() -> void:
	native_kernel = load("res://scripts/combat/native_swarm_loader.gd").create()
	check(native_kernel != null, "Native low-obstacle test requires the built kernel")
	if not native_kernel: quit(1); return
	await super.run()
