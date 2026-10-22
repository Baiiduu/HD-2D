extends Resource

@export var endpoint := ""
@export var board_id := "world-demo-v1"
@export var certificate_name := "leaderboard.hd2d.internal"
@export_multiline var trusted_ca_pem := ""
@export_range(3.0, 30.0, 1.0) var timeout_seconds := 10.0
