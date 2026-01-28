extends StagehandController
class_name StagehandRookie
## Rookie stagehand - fast but weak, can only carry light props (weight 1)

func _init() -> void:
	stagehand_name = "Rookie"
	strength = 1
	movement_speed = 180.0
	stagehand_radius = 12.0
