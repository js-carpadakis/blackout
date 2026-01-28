extends Node
## Global game state manager
## Handles game state transitions, level management, and global signals

signal game_state_changed(new_state: GameState)
signal phase_changed(new_phase: Phase)
signal level_completed(level_id: int, stars: int)

enum GameState { MENU, PLAYING, PAUSED, LEVEL_COMPLETE }
enum Phase { PLANNING, EXECUTION }

var current_state: GameState = GameState.MENU
var current_phase: Phase = Phase.PLANNING
var current_level_id: int = 0


func change_state(new_state: GameState) -> void:
	if current_state != new_state:
		current_state = new_state
		game_state_changed.emit(new_state)


func change_phase(new_phase: Phase) -> void:
	if current_phase != new_phase:
		current_phase = new_phase
		phase_changed.emit(new_phase)


func start_level(level_id: int) -> void:
	current_level_id = level_id
	current_phase = Phase.PLANNING
	change_state(GameState.PLAYING)


func start_execution() -> void:
	change_phase(Phase.EXECUTION)


func complete_level(stars: int) -> void:
	level_completed.emit(current_level_id, stars)
	change_state(GameState.LEVEL_COMPLETE)


func return_to_menu() -> void:
	change_state(GameState.MENU)
