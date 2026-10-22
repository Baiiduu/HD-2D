extends SceneTree
## 无界面坐标变换契约：旋转不能改变非正方形素材的局部宽高或制造剪切。
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func dimensions(basis: Basis, size: Vector2, label: String) -> void:
	check(is_equal_approx(basis.x.length(), size.x) and is_equal_approx(basis.y.length(), size.y), label + " preserves local dimensions")
	check(absf(basis.x.dot(basis.y)) < 0.00001, label + " has no shear")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.rotation_degrees = Vector3(-32, 135, 0)
	var mirror: MirrorProjectileEffect = load("res://scenes/combat/mirror_projectile_effect.tscn").instantiate()
	var mark: MirrorMarkEffect = load("res://scenes/combat/mirror_mark_effect.tscn").instantiate()
	var prism: PrismRicochetEffect = load("res://scenes/combat/prism_ricochet_effect.tscn").instantiate()
	var seed := EnemySeedProjectile.new()
	for node in [mirror, mark, prism, seed]: scene.add_child(node)
	var seed_texture := seed._texture
	seed._texture = mirror.head_texture
	seed._camera = camera
	for heading in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
		mirror._orient(mirror._head, Vector3.ZERO, heading, camera)
		dimensions(mirror._head.global_basis, mirror.head_texture.get_size() * mirror.pixel_size, "Mirror projectile")
		mark.normal = heading
		mark._update_pose(Vector3.ZERO, camera.global_basis)
		dimensions(mark._sprite.global_basis, mark.mirror_texture.get_size() * mark.pixel_size, "Mirror surface")
		prism.launch(Vector3.ZERO, heading, 2.0)
		var size := prism.head_texture.get_size()
		dimensions(prism._head.global_basis, Vector2(prism.head_width * 2.0, prism.head_width * 2.0 * size.y / size.x), "Prism projectile")
		seed.active = true
		seed.direction = heading
		seed._process(0.0)
		dimensions(seed._visual.global_basis, seed._texture.get_size() * 0.016, "Enemy seed")
	seed._texture = seed_texture
	scene.free()
	await process_frame
	print(JSON.stringify({"suite":"projectile_geometry", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
