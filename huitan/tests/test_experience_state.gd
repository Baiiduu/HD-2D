extends SceneTree

var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func run() -> void:
	var rules := ExperienceRules.new()
	var state := RunGrowthState.new()
	state.rules = rules
	check(state.level == 1 and state.experience == 0 and state.pending_choices == 0, "Fresh run starts at level one")
	check(rules.required_for(1) == 10 and rules.required_for(2) == 15 and rules.required_for(3) == 20, "Configurable level curve")
	check(state.add_experience(-5) == 0 and state.add_experience(0) == 0 and state.total_experience == 0, "Invalid experience cannot affect progress")
	check(state.add_experience(9) == 0 and state.experience == 9, "Experience below the threshold is retained")
	check(state.add_experience(2) == 1 and state.level == 2 and state.experience == 1, "Threshold crossing retains overflow")
	check(state.pending_choices == 1 and state.next_choice_level() == 2, "One choice per gained level")
	check(state.complete_choice() and not state.complete_choice(), "Choices cannot be consumed twice")
	state.reset()
	check(state.add_experience(52) == 3 and state.level == 4 and state.experience == 7, "One large collection supports multiple levels")
	check(state.pending_choices == 3 and state.next_choice_level() == 2, "Multi-level choices begin at the earliest level")
	state.complete_choice()
	check(state.next_choice_level() == 3, "Choice queue advances in order")
	state.discard_pending_choices()
	check(state.pending_choices == 0 and state.level == 4, "Run ending can discard pending interaction while preserving a result snapshot")
	rules.level_cap = 4
	state.reset()
	state.add_experience(100)
	check(state.level == 4 and state.experience == 0 and state.required_experience() == 0, "Cap stops the curve without a zero-threshold loop")
	check(state.add_experience(10) == 0 and state.pending_choices == 3 and state.total_experience == 110, "Cap cannot create extra choices but cumulative collection stays accurate")
	state.reset()
	check(state.total_experience == 0 and state.level == 1 and state.pending_choices == 0, "Retry resets all run-local progress")
	rules.curve_increase = 2
	check(rules.required_for(3) == 28, "Quadratic curve component is configurable")
	var pickup := ExperiencePickup.new()
	root.add_child(pickup)
	pickup.global_position = Vector3(2, 0, 0)
	check(not pickup.advance(0.1, Vector3.ZERO, 1, 0.3, 1, 2, 12, 8) and not pickup.attracting, "Out-of-range drops remain in place")
	check(not pickup.advance(0.1, Vector3(2, 2, 0), 3, 0.3, 1, 2, 12, 8) and not pickup.attracting, "Height tolerance prevents collecting from another distant terrace")
	check(not pickup.advance(0.1, Vector3.ZERO, 3, 0.3, 1, 2, 12, 8) and pickup.attracting, "Near drops enter attraction")
	for frame in 30:
		if pickup.advance(0.1, Vector3(-2, 0, 0), 0.1, 0.3, 1, 2, 12, 8): break
	check(pickup.collected and pickup.global_position.distance_to(Vector3(-2, 0, 0)) <= 0.3, "Attracted drops keep following a moving collection point")
	check(not pickup.advance(0.1, Vector3(-2, 0, 0), 3, 0.3, 1, 2, 12, 8), "One pickup cannot complete twice")
	pickup.free()
	print("Experience state/pickup: %d checks passed" % checks)
	quit.call_deferred()
