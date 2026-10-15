extends SceneTree

func _initialize() -> void:
	var folder := "D:/Project/HD-2DMap/artifacts/lamp-visual/"
	var before := Image.load_from_file(folder + "before-lamp.png")
	var after := Image.load_from_file(folder + "after-lamp.png")
	var region := Rect2i(260, 105, 470, 460)
	var comparison := Image.create(952, 460, false, Image.FORMAT_RGB8)
	comparison.fill(Color(0.08, 0.08, 0.1))
	comparison.blit_rect(before, region, Vector2i.ZERO)
	comparison.blit_rect(after, region, Vector2i(482, 0))
	var error := comparison.save_png(folder + "comparison.png")
	quit(0 if error == OK else 1)
