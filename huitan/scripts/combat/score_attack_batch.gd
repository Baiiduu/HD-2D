extends RefCounted
## One attack's shared score context. No scene nodes or global batch registry.

var owner_id := 0
var epoch := 0
var multiplier_milli := 1000
## Lock on first scored kill: sword contacts may queue several attacks per frame.
var locked := false
var kills := 0
var rewarded := 0
