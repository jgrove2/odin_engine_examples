# LDtk Integration Plan: Pilot → MVP → V1

## Overview

This document outlines a phased approach to integrating LDtk level editor support into the Odin engine. The plan is divided into three major phases:

- **Pilot**: Basic tile layer loading and entity placement validation
- **MVP**: Hardcoded properties and grid-based collision support
- **V1**: Dynamic properties, animations, multiple tilesets, and parallax

**Total Estimated Effort**: 46-56 hours (excluding optional Tiled support)

---

## Key Decisions & Constraints

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Physics Approach** | Grid-based tile collision (Option 2) | Efficient, LDtk-native support, can upgrade to physics later |
| **Asset Management** | Texture caching required for MVP | Sprites must be loaded from disk |
| **Asset Paths** | Asset folder paths + relative resolution | Flexibility for project structure |
| **Error Handling** | Engine-wide error system (Phase 0) | Better diagnostics from day one |
| **Properties (MVP)** | Hardcoded property matching | Simple implementation, fast iteration |
| **Properties (V1)** | Dynamic key-value system | Full flexibility for custom fields |
| **Multi-Tileset (MVP)** | Single tileset only | Simpler implementation; V1 feature |
| **Animations (MVP)** | Not included | V1 feature with full animation system |
| **Parallax (MVP)** | Not included | V1 feature; single layer rendering sufficient |
| **Debug Viewer** | Basic overlay in Pilot, enhanced in MVP | Validation and development aid |
| **Tiled Format** | Optional V1 feature | Focus on LDtk first; Tiled as extension |

---

## Phase 0: Foundation & Infrastructure

These systems enable all downstream phases and should be built first. No LDtk-specific code; these are general engine utilities.

### 0.1: Error Handling System

**File**: `engine/core/error.odin` (new)

**Scope**:
- Define `Error_Kind` enum with common errors:
  - `File_Not_Found`
  - `Parse_Error`
  - `Invalid_Asset`
  - `Invalid_Property`
  - `Collision_Error`
  - etc.
- Create `Result(T)` type wrapping `union(T, Error)`
- Error context/logging system with stack traces
- Propagation macros/helpers for Odin

**Why Now**: Required by all downstream loaders; better error reporting from day one

**Complexity**: Medium  
**Estimate**: 1-2 hours

**Deliverables**:
- Error type definitions
- Result wrapper type
- Error logging infrastructure

---

### 0.2: File I/O Abstraction

**File**: `engine/core/file.odin` (new)

**Scope**:
- `read_file_to_string(path: string) -> Result(string)` — Read entire file into memory
- `file_exists(path: string) -> bool` — Check if file exists
- Path resolution — Handle relative paths (relative to executable or LDtk file)
- Graceful missing file handling

**Why Now**: Needed by JSON parser and asset loader

**Complexity**: Low  
**Estimate**: 30 minutes

**Deliverables**:
- File reading function with error handling
- Path resolution utilities

---

### 0.3: Asset Manager (Core)

**File**: `engine/assets/manager.odin` (new)

**Scope**:
- `Asset_Manager` struct with texture cache: `map[string]rl.Texture2D`
- `load_texture(manager: *Asset_Manager, path: string) -> Result(rl.Texture2D)`
  - Cache hits avoid reloading
  - Error handling for missing/invalid image files
- `cleanup()` proc to free all loaded textures on shutdown
- Support asset folder paths (e.g., `assets/tilesets/dungeon.png`)

**Why Now**: Required immediately by tile renderer and sprite loader

**Complexity**: Medium  
**Estimate**: 1 hour

**Deliverables**:
- Asset manager struct and core functions
- Texture caching mechanism
- Resource cleanup

---

### 0.4: JSON Parser (Simple)

**File**: `engine/formats/json.odin` (new)

**Scope**:
- Minimal JSON parser for LDtk format
- Parse objects, arrays, strings, numbers, booleans, null
- No external dependencies (pure Odin)
- Return generic `JSON_Value` type supporting queries
- Error handling with line/column reporting
- Basic query functions: `get_string()`, `get_number()`, `get_array()`, etc.

**Why Now**: Foundation for all LDtk loaders

**Complexity**: High (most complex foundation task)  
**Estimate**: 3-4 hours

**Deliverables**:
- JSON parser implementation
- JSON_Value type with query interface
- Error reporting system

---

## Phase 1: Pilot (Basic Tile Layer + Entity Placement)

**Goal**: Load a simple LDtk file, render tiles, spawn entities at their positions. Validate the architecture before building MVP.

**Dependencies**: All of Phase 0

**Estimated Duration**: 11-13 hours

---

### 1.1: LDtk JSON Schema Understanding

**File**: `docs/ldtk_schema.md` (new)

**Scope**:
- Document LDtk JSON structure (minimal subset needed for Pilot)
- Key fields:
  - `worlds` / `levels` — Level metadata
  - `tilesets` — Tileset definitions (image path, tile size)
  - `layerInstances` — Layer data (tiles, entities)
  - `entityInstances` — Spawned entities (position, size, type, properties)
  - Tile positioning and grid system
  - Entity grid positioning vs pixel positioning
- LDtk coordinate system explanation

**Why Now**: Reference for parser implementation

**Complexity**: Low (documentation)  
**Estimate**: 30 minutes

**Deliverables**:
- Schema documentation with examples
- Field reference for common LDtk structures

---

### 1.2: LDtk Tile Layer Parser

**File**: `engine/formats/ldtk.odin` (new)

**Scope**:
- Parse single tileset reference from LDtk JSON
- Parse tile layer data:
  - Grid dimensions (width, height in tiles)
  - Tile size (usually 16x16 or configurable)
  - Grid of tile IDs
  - Offset/position
- Handle tile encoding (check if RLE or flat array)
- Return `Tile_Layer` struct with:
  ```odin
  Tile_Layer :: struct {
    tiles: []i32,              // Flat array of tile IDs
    width: i32,
    height: i32,
    tile_size: i32,
    offset_x: i32,
    offset_y: i32,
    tileset_path: string,
  }
  ```

**Why Now**: Core of tile rendering

**Complexity**: Medium  
**Estimate**: 2 hours

**Deliverables**:
- Tile layer parsing function
- Tile_Layer struct definition
- Tile ID extraction logic

---

### 1.3: LDtk Entity Parser (Basic)

**File**: `engine/formats/ldtk.odin` (add to 1.2)

**Scope**:
- Parse entity instances from LDtk JSON
- Extract per entity:
  - Position (x, y in pixels)
  - Size (width, height)
  - Entity identifier/type (string)
  - Ignore properties for now (Pilot doesn't use them)
- Return `Entity_Spawn_Data` struct:
  ```odin
  Entity_Spawn_Data :: struct {
    entity_type: string,
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
  }
  ```

**Why Now**: Spawn entities in correct positions

**Complexity**: Low-Medium  
**Estimate**: 1 hour

**Deliverables**:
- Entity spawn data parsing
- Entity_Spawn_Data struct

---

### 1.4: Tile Renderer System

**File**: `engine/render/tile_renderer.odin` (new)

**Scope**:
- `Tile_Layer_Renderer` component:
  ```odin
  Tile_Layer_Renderer :: struct {
    tile_layer: Tile_Layer,
    tileset_texture: rl.Texture2D,
  }
  ```
- Rendering system that draws tile layers each frame
- For each tile in the layer:
  - Calculate grid position → pixel position
  - Extract tileset UV coordinates from tile ID
  - Draw quad with correct texture region
- Handle camera offset/zoom

**Why Now**: Visualize loaded level

**Complexity**: Medium  
**Estimate**: 2-3 hours

**Deliverables**:
- Tile_Layer_Renderer component
- System function for rendering
- Tileset UV calculation logic

---

### 1.5: LDtk Level Loader (Pilot)

**File**: `engine/loaders/ldtk_loader.odin` (new)

**Scope**:
- Main orchestration function: `load_ldtk_level(world: *ecs.World, path: string, asset_manager: *Asset_Manager) -> Result(Level_Metadata)`
- Steps:
  1. Read LDtk JSON file
  2. Parse level metadata
  3. Parse tileset reference + load tileset texture via asset manager
  4. Parse tile layer
  5. Spawn tile layer entity with `Tile_Layer_Renderer` component
  6. Parse entity instances
  7. For each entity, post spawn command (basic type → component mapping)
  8. Return level metadata (for debug info)
- Return `Result` type for error handling

**Why Now**: Orchestrate all Pilot components

**Complexity**: Medium  
**Estimate**: 1.5 hours

**Deliverables**:
- Main level loader function
- Level metadata struct
- Basic entity spawning based on type

---

### 1.6: Pilot Example

**File**: `examples/ldtk_pilot/main.odin` (new)

**Scope**:
- Create minimal LDtk test file:
  - One 16x12 tile layer with a simple tileset (create or use existing)
  - 3-5 entity instances at various positions (Player, Enemy, NPC types)
  - Minimal setup
- Load level via `ldtk_loader`
- Display tiles + entity positions on screen
- Basic debug overlay showing entity names/types
- Frame rate counter

**Why Now**: Validate Pilot implementation

**Complexity**: Low  
**Estimate**: 1 hour

**Deliverables**:
- Working example with test LDtk file
- Basic game loop integration

---

### 1.7: Debug Viewer (Pilot)

**File**: `engine/debug/level_viewer.odin` (new)

**Scope**:
- On-screen overlay showing:
  - Tile grid (optional, can be toggled)
  - Entity positions as colored dots/squares
  - Entity type labels above each entity
  - Frame rate
  - Loaded asset count
  - Camera position/zoom
- Toggle on/off with key (e.g., `D` key)
- Render as overlay on top of game

**Why Now**: Validate loaded data visually during development

**Complexity**: Low  
**Estimate**: 1 hour

**Deliverables**:
- Debug viewer component/system
- Overlay rendering
- Toggle input handling

---

## Phase 2: MVP (Hardcoded Properties + Grid Collision)

**Goal**: Fully playable level loading with basic gameplay properties and collision support.

**Dependencies**: All of Phases 0 and 1

**Estimated Duration**: 14-18 hours

---

### 2.1: Hardcoded Property System

**File**: `engine/formats/ldtk_properties.odin` (new)

**Scope**:
- Define `Entity_Properties` struct with common fields:
  ```odin
  Entity_Properties :: struct {
    entity_type: string,      // Player, Enemy, NPC, Spawner, etc.
    speed: f32,               // Movement speed
    health: i32,              // Hit points
    behavior: string,         // AI behavior type (Patrol, Chase, Idle, etc.)
    damage: f32,              // Damage dealt (for enemies/weapons)
    spawn_delay: f32,         // For spawners
    // Add more as needed
  }
  ```
- Parse LDtk custom fields into this struct (hardcoded key matching)
- Fallback defaults if properties missing:
  ```odin
  speed: 100.0
  health: 10
  behavior: "Idle"
  damage: 1.0
  spawn_delay: 5.0
  ```

**Why Now**: Entities need gameplay data

**Complexity**: Low-Medium  
**Estimate**: 1-1.5 hours

**Deliverables**:
- Entity_Properties struct definition
- Default value system
- Property extraction logic

---

### 2.2: Enhanced Entity Parser (Properties)

**File**: `engine/formats/ldtk.odin` (enhance from 1.3)

**Scope**:
- Extend `Entity_Spawn_Data` to include `Entity_Properties`
- Parse LDtk custom fields from JSON:
  - Match LDtk field names to `Entity_Properties` fields
  - Type conversion (string → f32, i32, etc.)
  - Handle missing fields with defaults
- Return enhanced spawn data with properties populated

**Why Now**: Enable property-driven gameplay

**Complexity**: Low  
**Estimate**: 1 hour

**Deliverables**:
- Enhanced entity parsing
- Property extraction from JSON

---

### 2.3: Tileset Collision Data Parser

**File**: `engine/formats/ldtk.odin` (add to)

**Scope**:
- Parse tileset's collision metadata from LDtk
- LDtk stores collision per tile in the tileset definition
- Build collision grid: `map[tile_id]Collision_Type`
  ```odin
  Collision_Type :: enum {
    Empty,
    Solid,
    Platform,
    Spike,
    Water,
    // Add more as needed
  }
  ```
- Or simpler for MVP: `map[tile_id]bool` (is_solid)
- Return `Tileset_Collision_Data` struct

**Why Now**: Enable collision queries

**Complexity**: Medium  
**Estimate**: 1.5 hours

**Deliverables**:
- Collision data parsing from tileset
- Collision grid data structure
- Collision type definitions

---

### 2.4: Collision Query System

**File**: `engine/physics/collision.odin` (new)

**Scope**:
- `Collision_Grid` component:
  ```odin
  Collision_Grid :: struct {
    collision_data: map[i32]Collision_Type,  // tile_id → collision type
    tile_size: f32,
    offset_x: f32,
    offset_y: f32,
  }
  ```
- Query functions:
  - `is_tile_solid(grid: *Collision_Grid, world_pos: Vector2) -> bool`
  - `get_collision_type(grid: *Collision_Grid, world_pos: Vector2) -> Collision_Type`
  - `get_tile_at_pos(grid: *Collision_Grid, world_pos: Vector2) -> i32`
- Handle grid offset and tile size
- No physics engine yet—just data queries and collision checks

**Why Now**: Enable player/enemy movement validation

**Complexity**: Low-Medium  
**Estimate**: 1.5 hours

**Deliverables**:
- Collision_Grid component
- Query functions for collision checks
- World position → grid position conversion

---

### 2.5: Entity Spawner System

**File**: `engine/systems/entity_spawner.odin` (new)

**Scope**:
- `Entity_Spawn_Command` event type:
  ```odin
  Entity_Spawn_Command :: struct {
    spawn_data: Entity_Spawn_Data,
    properties: Entity_Properties,
  }
  ```
- Spawner system that consumes `Entity_Spawn_Command` events
- Spawn logic maps entity types to component combinations:
  - `"Player"` → `Position` + `Player_Input` + `Velocity` + `Sprite` + `Health` + `Game_Control`
  - `"Enemy"` → `Position` + `Velocity` + `Sprite` + `AI_Controller` + `Health`
  - `"NPC"` → `Position` + `Sprite` + `Dialog_Data`
  - `"Spawner"` → `Position` + `Enemy_Spawner`
  - etc.
- Assign properties from LDtk to components (e.g., `Health.max_health = properties.health`)
- Handle unknown entity types gracefully (warn or skip)

**Why Now**: Convert LDtk data to playable entities

**Complexity**: Medium  
**Estimate**: 2 hours

**Deliverables**:
- Entity_Spawn_Command event type
- Entity type → component mapping logic
- Spawner system function
- Property assignment

---

### 2.6: Enhanced LDtk Loader (MVP)

**File**: `engine/loaders/ldtk_loader.odin` (enhance from 1.5)

**Scope**:
- Extend Phase 1 loader to include:
  - Parse collision grid data from tileset
  - Create `Collision_Grid` entity in the world
  - Post `Entity_Spawn_Command` events with properties
  - Comprehensive error handling:
    - Invalid files
    - Missing assets
    - Malformed JSON
- Return `Result` type

**Why Now**: Full MVP integration

**Complexity**: Low  
**Estimate**: 1 hour

**Deliverables**:
- Enhanced loader with collision support
- Property-aware entity spawning
- Better error messages

---

### 2.7: MVP Example + Integration

**File**: `examples/ldtk_example/` or integrate into existing example

**Scope**:
- Create LDtk test level with:
  - 20x15 tile layer with mixed solid/platform tiles
  - Player spawn point with properties (speed: 150, health: 20)
  - 3-5 enemies scattered around (health: 5, speed: 80, behavior: "Patrol")
  - 1-2 NPCs (static, for future dialog)
  - Clear collision zones (walls, platforms, hazards)
- Load level and play:
  - Player moves with arrow keys/WASD
  - Movement blocked by solid tiles
  - Can walk on platform tiles
  - Basic enemy AI (patrol within area)
- Validate collision system works

**Why Now**: End-to-end validation

**Complexity**: Medium  
**Estimate**: 2-3 hours

**Deliverables**:
- Working playable example
- LDtk test level file
- Integration with game systems

---

### 2.8: Enhanced Debug Viewer (MVP)

**File**: `engine/debug/level_viewer.odin` (enhance from 1.7)

**Scope**:
- Show collision visualization:
  - Solid tiles in red outline
  - Platform tiles in blue outline
  - Water/hazard tiles in different colors
- Entity properties overlay:
  - Display entity name, type, health, speed
  - Update in real-time during gameplay
- Toggle collision visualization with key (e.g., `C`)
- Show collision grid overlay

**Why Now**: Validate collision data during development

**Complexity**: Low  
**Estimate**: 1 hour

**Deliverables**:
- Enhanced debug overlay
- Collision visualization
- Property display

---

## Phase 3: V1 (Dynamic Properties, Animations, Multiple Tilesets, Parallax)

**Goal**: Full-featured level loading with rich visual effects and maximum flexibility.

**Dependencies**: All of Phases 0, 1, and 2

**Estimated Duration**: 15-18 hours

---

### 3.1: Dynamic Property System

**File**: `engine/formats/ldtk_properties.odin` (refactor from 2.1)

**Scope**:
- Replace hardcoded `Entity_Properties` with generic key-value system
- Parse any LDtk custom field regardless of name
- Store as `map[string]JSON_Value` on entities
- Provide query functions:
  - `get_property_string(entity: Entity, key: string, default: string) -> string`
  - `get_property_int(entity: Entity, key: string, default: i32) -> i32`
  - `get_property_float(entity: Entity, key: string, default: f32) -> f32`
  - `get_property_bool(entity: Entity, key: string, default: bool) -> bool`
- Allow game code to query arbitrary properties

**Why Now**: Full flexibility for custom game data

**Complexity**: Medium  
**Estimate**: 2 hours

**Deliverables**:
- Generic property storage system
- Property query functions
- Type conversion helpers

---

### 3.2: Animated Tiles

**File**: `engine/render/animated_tiles.odin` (new)

**Scope**:
- Parse animation data from LDtk tileset metadata
  - LDtk defines animations per tile with frame list and timing
- `Animated_Tile` component:
  ```odin
  Animated_Tile :: struct {
    tile_id: i32,
    animation: Tile_Animation,
    current_frame: i32,
    elapsed_time: f32,
  }
  ```
- `Tile_Animation` struct:
  ```odin
  Tile_Animation :: struct {
    frames: []i32,           // Frame tile IDs
    frame_duration: f32,     // Time per frame
    loop: bool,
  }
  ```
- Animation system that updates frame index each tick
- Tile renderer checks if tile is animated and draws current frame

**Why Now**: Enable animated background elements

**Complexity**: Medium-High  
**Estimate**: 2-3 hours

**Deliverables**:
- Animation data parsing
- Animated_Tile component
- Animation update system

---

### 3.3: Multiple Tileset Support

**File**: `engine/formats/ldtk.odin` (enhance)

**Scope**:
- Parse multiple tilesets per level (LDtk supports this natively)
- Tile ID mapping across tilesets:
  - LDtk uses firstgid offset to distinguish tile IDs per tileset
  - Map global tile ID → (tileset_index, local_tile_id)
- Asset manager loads all referenced tilesets
- Tile renderer selects correct texture per tile:
  - For each tile in layer, determine which tileset it belongs to
  - Draw from appropriate texture

**Why Now**: Support complex multi-tileset levels

**Complexity**: Medium  
**Estimate**: 2 hours

**Deliverables**:
- Multi-tileset parsing
- Tile ID mapping logic
- Multi-texture rendering

---

### 3.4: Parallax Layer System

**File**: `engine/render/parallax.odin` (new)

**Scope**:
- Parse layer offset/parallax factor from LDtk
- `Parallax_Layer` component:
  ```odin
  Parallax_Layer :: struct {
    tile_layer: Tile_Layer,
    tileset_texture: rl.Texture2D,
    parallax_factor_x: f32,  // 0.0 = static, 1.0 = moves with camera
    parallax_factor_y: f32,
  }
  ```
- Rendering system that adjusts camera offset per layer:
  - Calculate effective camera position: `camera_pos * parallax_factor`
  - Draw tile layer with adjusted offset
- Multiple tile layers render in order with different offsets

**Why Now**: Enable visual depth with parallax scrolling

**Complexity**: Medium  
**Estimate**: 2 hours

**Deliverables**:
- Parallax data parsing
- Parallax_Layer component
- Parallax rendering system

---

### 3.5: Scene/Level Manager

**File**: `engine/scenes/level_manager.odin` (new)

**Scope**:
- `Level_Manager` system for managing game levels
- Functions:
  - `load_level(level_path: string)` — Queue level load
  - `unload_current_level()` — Queue level unload
  - `next_level()` / `previous_level()` — Navigate level list
- Level transitions:
  - Finish current frame
  - Clean up current world (free all entities)
  - Load new level into world
  - Execute next frame
- Support multiple levels in a project file
- Graceful error handling for missing levels

**Why Now**: Enable multi-level games with smooth transitions

**Complexity**: Medium  
**Estimate**: 2 hours

**Deliverables**:
- Level_Manager struct and functions
- Level queuing/transition system
- Cleanup/unload logic

---

### 3.6: Tiled Format Support (Optional)

**File**: `engine/formats/tiled.odin` (new)

**Scope**:
- Add Tiled TMX JSON parser (similar architecture to LDtk)
- Parse Tiled-specific fields:
  - Tilesets
  - Tile layers
  - Object layers
  - Custom properties
- Unify interface so both LDtk and Tiled use same spawner system
- Determine entity mapping from Tiled object types

**Why Now**: Support alternative level editor

**Complexity**: High  
**Estimate**: 4-5 hours

**Deliverables**:
- Tiled TMX parser
- Unified loader interface
- Format abstraction layer

---

## Task Breakdown by Phase

| Phase | Component | Estimate | Phase Total |
|-------|-----------|----------|-------------|
| **Phase 0: Foundation** | Error System | 1-2h | **6-7h** |
| | File I/O | 0.5h | |
| | Asset Manager | 1h | |
| | JSON Parser | 3-4h | |
| **Phase 1: Pilot** | Schema Docs | 0.5h | **11-13h** |
| | Tile Parser | 2h | |
| | Entity Parser | 1h | |
| | Tile Renderer | 2-3h | |
| | LDtk Loader | 1.5h | |
| | Example + Test Level | 1h | |
| | Debug Viewer | 1h | |
| **Phase 2: MVP** | Hardcoded Properties | 1-1.5h | **14-18h** |
| | Property Parser | 1h | |
| | Collision Parser | 1.5h | |
| | Collision Queries | 1.5h | |
| | Entity Spawner | 2h | |
| | Enhanced Loader | 1h | |
| | Example + Level | 2-3h | |
| | Debug Viewer | 1h | |
| **Phase 3: V1** | Dynamic Properties | 2h | **15-18h** |
| | Animated Tiles | 2-3h | |
| | Multi-Tileset | 2h | |
| | Parallax | 2h | |
| | Level Manager | 2h | |
| | Tiled Support | 4-5h (opt) | |
| **TOTAL** | | | **46-56h** (without Tiled) |

---

## Build Order & Dependencies

```
Phase 0 (Foundation - must build first)
├── Error System
├── File I/O
├── Asset Manager (depends on Error, File I/O)
└── JSON Parser (depends on Error, File I/O)

Phase 1 (Pilot - depends on Phase 0)
├── Schema Docs
├── Tile Parser (depends on JSON Parser)
├── Entity Parser (depends on JSON Parser)
├── Tile Renderer (depends on Asset Manager)
├── LDtk Loader (depends on all parsers + Asset Manager)
├── Pilot Example (depends on LDtk Loader)
└── Debug Viewer (depends on Pilot Example)

Phase 2 (MVP - depends on Phase 0 & 1)
├── Hardcoded Property System
├── Property Parser (depends on JSON Parser + Hardcoded Properties)
├── Collision Parser (depends on JSON Parser)
├── Collision Query System (depends on Collision Parser)
├── Entity Spawner (depends on all above + existing ECS)
├── Enhanced LDtk Loader (depends on all above)
├── MVP Example (depends on Enhanced Loader)
└── Enhanced Debug Viewer (depends on MVP Example)

Phase 3 (V1 - depends on Phase 2)
├── Dynamic Properties (depends on Property System)
├── Animated Tiles (depends on Tile Renderer)
├── Multi-Tileset (depends on LDtk Loader)
├── Parallax (depends on Tile Renderer)
├── Level Manager (depends on LDtk Loader)
└── Tiled Support (depends on JSON Parser + LDtk structure)
```

---

## Key Design Patterns

### Error Handling
- All loaders return `Result(T)` type for proper error propagation
- Errors include context (line/column for parse errors, file path for file errors)
- Game code checks results and handles gracefully

### ECS Integration
- Level data is fully converted to ECS entities
- No monolithic "Level" object—just a collection of entities
- Components define behavior; systems implement logic
- Events coordinate between systems

### Asset Management
- All external resources (textures, data) go through Asset_Manager
- Caching prevents reload overhead
- Single source of truth for loaded assets

### Properties System
- MVP: Hardcoded property matching for fast iteration
- V1: Dynamic system for unlimited flexibility
- Query functions provide type-safe property access

### Collision
- Grid-based for efficiency (no physics engine dependency)
- Can upgrade to physics later without breaking existing code
- Collision data attached to level (not per-entity)

---

## Questions to Address Before Implementation

1. **Test Level**: Do you have an existing LDtk file, or should one be created during the Pilot phase?

2. **Component Definitions**: Should new components (Player_Input, AI_Controller, Health, etc.) be created in:
   - `engine/components/` (shared, reusable)?
   - Game-specific locations?
   - Or extend existing components?

3. **Priority**: Are you ready to start Phase 0, or want to refine anything first?

4. **Tiled Format**: Priority for V1, or defer to later?

---

## Success Criteria

### Pilot Phase Complete
- ✅ Reads LDtk JSON files without crashing
- ✅ Renders tile layer correctly
- ✅ Spawns entities at correct positions
- ✅ Debug viewer displays all data accurately

### MVP Phase Complete
- ✅ Entities have gameplay properties (speed, health, behavior)
- ✅ Collision system prevents movement through solid tiles
- ✅ Enemies patrol using hardcoded properties
- ✅ Player can move and interact with environment
- ✅ Multiple test levels load and play correctly

### V1 Phase Complete
- ✅ Dynamic properties work for arbitrary LDtk fields
- ✅ Animated tiles play correctly
- ✅ Multiple tilesets per level work
- ✅ Parallax layers scroll correctly
- ✅ Level transitions work smoothly
- ✅ (Optional) Tiled format loading works identically to LDtk
