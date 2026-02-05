# Blackout (Very Early WIP)

A theater stage prop management puzzle game built with Godot 4.5. Coordinate stagehands to move props across the stage during a blackout — plan your routes, assign your crew, and execute before the lights come back on.

## Gameplay

The game alternates between two phases:

### Planning Phase

Survey the stage and create movement plans for each prop:

- **Assign stagehands** to props (right-click a prop with a stagehand selected)
- **Set destinations** by dragging prop target ghosts to where they need to go
- **Build multi-leg routes** — chain multiple movement segments so a prop can be relayed between stagehands or repositioned in stages
- **Assign clear zones** — stagehands must be standing in clear zones (top-left / top-right) when the blackout ends

### Execution Phase (Blackout)

Press Space to start the blackout. Props drive the action:

1. Stagehands are dispatched to their assigned props
2. They pick up the prop (cooperative carry for heavy ones)
3. They transport it to the leg's destination
4. If more legs remain, the next group takes over
5. Execution ends when all props are delivered and all stagehands are in position

## Stagehand Types

| Type    | Speed | Strength | Description            |
|---------|-------|----------|------------------------|
| Rookie  | Fast  | 1        | Quick but can only carry light props |
| Regular | Medium| 2        | Balanced all-rounder   |
| Strong  | Slow  | 3        | Handles the heaviest props |

Props have weight values (1–3). If a prop is too heavy for one stagehand, assign multiple — they'll carry it cooperatively with synchronized movement.

## Controls

| Input | Action |
|-------|--------|
| Left-click | Select / drag stagehands and props |
| Right-click prop | Assign or unassign selected stagehand |
| Right-click clear zone | Assign stagehand to clear zone |
| Drag target ghost | Reposition a prop's destination |
| Space | Start execution |
| W/A/S/D | Pan camera |
| Q/E | Zoom out / in |
| Tab | Switch camera view (stage-left / stage-right) |

## Project Structure

```
scripts/
├── autoloads/
│   └── game_manager.gd           # Global game state and phase management
├── core/
│   ├── game_session.gd           # Main game loop — planning input + execution
│   └── pathfinding_manager.gd    # Grid-based navigation
├── entities/
│   ├── prop_controller.gd        # Prop entity with movement plan legs
│   ├── stagehand_controller.gd   # Base stagehand with carrying mechanics
│   ├── stagehand_rookie.gd
│   ├── stagehand_regular.gd
│   └── stagehand_strong.gd
├── stage/
│   ├── camera_controller.gd      # Top-down camera with view switching
│   ├── grid_system.gd            # Grid overlay and navigation mesh
│   └── stage_zones.gd            # Clear zones and stage boundaries
└── ui/
    └── planning_hud.gd           # Planning phase HUD and task panel
```

## Architecture

The project uses a **prop-centric data model** — movement plans live on props, not stagehands. Each prop holds an array of "legs," where each leg defines which stagehands carry it and where it goes:

```
movement_plan = [
  { "stagehands": [rookie1, regular1], "destination": Vector2(400, 300) },
  { "stagehands": [strong1],           "destination": Vector2(800, 200) }
]
```

During execution, props manage their own leg progression and dispatch stagehands as needed. This makes relay routes and multi-stagehand handoffs straightforward.

## Running the Project

1. Install [Godot 4.5](https://godotengine.org/download) or later
2. Clone this repository
3. Open the project in the Godot editor
4. Run the main scene (`scenes/main/main.tscn`)
