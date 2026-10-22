extends RefCounted
## Shared visual/audio clock. Cue crossings are bounded when a window stalls.
const CUES := {1.05: &"launch", 1.55: &"bounce", 1.94: &"hit", 2.22: &"flyby"}
const FLIGHT_TIMES := [1.05, 1.55, 1.94, 2.65]
const FLIGHT_POINTS := [Vector2(900, 588), Vector2(1040, 639), Vector2(1175, 449), Vector2(1580, 350)]
const FOOT_OFFSET := Vector2(0, 44)
var period := 11.0
var time := 0.0

static func hero_position(stamp: float) -> Vector2:
	if stamp < FLIGHT_TIMES[0]:
		return FLIGHT_POINTS[0] + Vector2(-14, 8) * smoothstep(0.15, FLIGHT_TIMES[0], stamp)
	for index in 3:
		if stamp < FLIGHT_TIMES[index + 1]:
			return FLIGHT_POINTS[index].lerp(FLIGHT_POINTS[index + 1], (stamp - FLIGHT_TIMES[index]) / (FLIGHT_TIMES[index + 1] - FLIGHT_TIMES[index]))
	if stamp < 5.0: return FLIGHT_POINTS[3]
	return FLIGHT_POINTS[3].lerp(FLIGHT_POINTS[0], smoothstep(5.0, 6.2, stamp))

static func flight_segments() -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for index in 3:
		segments.append({"start": FLIGHT_POINTS[index] + FOOT_OFFSET,
			"end": FLIGHT_POINTS[index + 1] + FOOT_OFFSET, "birth": FLIGHT_TIMES[index],
			"seconds": FLIGHT_TIMES[index + 1] - FLIGHT_TIMES[index]})
	return segments

func reset(start := 0.0) -> void:
	time = fposmod(start, maxf(period, 4.0))

func advance(delta: float) -> Array[StringName]:
	var events: Array[StringName] = []
	if not is_finite(delta) or delta <= 0.0: return events
	var duration := maxf(period, 4.0)
	var next := time + delta
	# Do not replay historical impacts after minimizing or a long load stall.
	if delta < duration:
		for stamp: float in CUES:
			if time < stamp and minf(next, duration) >= stamp:
				events.append(CUES[stamp])
		if next >= duration:
			for stamp: float in CUES:
				if next - duration >= stamp: events.append(CUES[stamp])
	time = fposmod(next, duration)
	return events
