class_name WorldEntryRequest
extends RefCounted
## 菜单开始按钮：request() 后切正式地图；切场失败时 clear()。
## 静态请求跨场景保留，由正式地图消费一次；不需要 Autoload。
static var _pending := false
static var _menu_pending := false

static func request_menu() -> void:
	_pending = false
	_menu_pending = true

static func consume_menu() -> bool:
	var requested := _menu_pending
	_menu_pending = false
	return requested

static func has_pending() -> bool:
	return _pending

static func request() -> void:
	_pending = true

static func consume() -> bool:
	var requested := _pending
	_pending = false
	return requested

static func clear() -> void:
	_pending = false
	_menu_pending = false
