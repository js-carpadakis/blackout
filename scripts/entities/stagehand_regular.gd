extends StagehandController
class_name StagehandRegular
## Regular stagehand - balanced speed and strength, can carry medium props (weight 1-2)

func _init() -> void:
	stagehand_name = "Regular"
	strength = 2
	movement_speed = 150.0
	stagehand_radius = 15.0
