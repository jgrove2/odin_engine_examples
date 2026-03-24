# ECS Architecture

The ECS (Entity Component System) is the core of the engine. It separates data (Components) from identity (Entities) and behavior (Systems), enabling cache-friendly iteration and clean separation of concerns.

## Entities

An entity is just an ID — a `u32` split into two parts:

```
| generation (8 bits) | index (24 bits) |
```

- **Index** (lower 24 bits): Position in the entity manager's arrays. Supports up to ~16 million entities.
- **Generation** (upper 8 bits): Incremented each time a slot is recycled. This prevents stale handles from accidentally referencing a new entity that reused the same index.

This is the **Generational Index** pattern (also called Generational Arena). It gives you the performance of array indexing with the safety of checking whether a handle is still valid.

**Key procs** (defined in `engine/ecs/entity.odin`):

| Proc | Purpose |
|---|---|
| `entity_index(e)` | Extract the 24-bit index from an entity ID |
| `entity_generation(e)` | Extract the 8-bit generation from an entity ID |
| `entity_create_id(index, gen)` | Pack an index + generation into an entity ID |
| `entity_spawn(em)` | Allocate a new entity (reuses freed slots via a free list) |
| `entity_kill(em, e)` | Free an entity slot and bump its generation |
| `entity_is_alive(em, e)` | Check if an entity handle is still valid (generation matches) |

### Entity Manager

The `Entity_Manager` struct holds:

- `generations: [dynamic]u8` — One generation counter per slot. Grows as new slots are needed.
- `free_list: [dynamic]u32` — Recycled slot indices. `entity_spawn` pops from here before allocating new slots.
- `alive_count: u32` — Number of currently alive entities.

When an entity is killed, its generation is bumped and the index is pushed onto the free list. The next `entity_spawn` call will reuse that slot with the new (higher) generation, so any old `Entity` handles pointing at that slot will fail the `entity_is_alive` check.

## Components

A component is a plain Odin struct — no base type, no interface, no methods:

```odin
Food :: struct {
    col, row: int,
}
```

Components hold only data. All behavior lives in systems. This separation is what makes ECS composable — you can attach any combination of components to any entity without inheritance hierarchies.

### Registering Components

Before a component type can be attached to entities, it must be registered with the World:

```odin
ecs.world_register_component(&world, Food)
```

This creates a `Sparse_Set` sized to hold `Food` values. Registration must happen before any `world_spawn_with` or `world_add_component` call for that type.

### Zero-Size Tag Components

Components with no fields (zero-size structs) are supported. The sparse set tracks which entities have the tag without storing any data. This is useful for markers like `Player`, `Enemy`, or `Dead`.

## Sparse Set

The sparse set is the storage backend for components. It provides:

- **O(1)** insert, remove, and lookup by entity index
- **Dense, packed iteration** — iterating all components of a type walks a contiguous array with no gaps

**Structure** (defined in `engine/ecs/sparse_set.odin`):

```
Sparse_Set :: struct {
    sparse:         [dynamic]u32,    // entity_index → dense_index (or SPARSE_EMPTY)
    dense:          [dynamic]u8,     // packed component data as raw bytes
    entities:       [dynamic]u32,    // dense_index → entity_index (parallel to dense)
    component_size: int,             // sizeof(T) for this component type
    count:          int,             // number of components stored
}
```

**How it works:**

1. **Insert**: `sparse[entity_idx] = count`, then append the component bytes to `dense` and the entity index to `entities`. O(1).
2. **Lookup**: `dense_idx = sparse[entity_idx]`, then read from `dense[dense_idx * component_size]`. O(1).
3. **Remove**: Swap the removed element with the last element in `dense` and `entities`, then decrement `count`. O(1), maintains dense packing.
4. **Iterate**: Walk `entities[0..count]` and `dense[0..count * component_size]` sequentially. Cache-friendly linear scan.

The tradeoff is memory: the `sparse` array may be larger than the number of entities if entity indices are spread out. This is acceptable for game-scale entity counts.

## World

The `World` is the top-level container that ties entities and components together (defined in `engine/ecs/world.odin`):

```odin
World :: struct {
    entities:   Entity_Manager,
    components: map[typeid]Sparse_Set,
}
```

The `components` map is keyed by `typeid`, so each component type has exactly one `Sparse_Set`. This means component lookup by type is a hash map lookup (done once per query, not per entity).

**Key procs:**

| Proc | Purpose |
|---|---|
| `world_create()` | Allocate a new World with empty entity manager and component map |
| `world_destroy(&w)` | Free all sparse sets, the component map, and the entity manager |
| `world_register_component(&w, T)` | Create a sparse set for type `T` |
| `world_spawn(&w)` | Allocate an entity with no components |
| `world_spawn_with(&w, component)` | Allocate an entity and attach a component in one call |
| `world_add_component(&w, e, component)` | Attach a component to an existing entity |
| `world_get_component(&w, e, T)` | Get a `^T` pointer to an entity's component (nil if missing) |
| `world_has_component(&w, e, T)` | Check if an entity has a component of type `T` |
| `world_remove_component(&w, e, T)` | Remove a component from an entity |
| `world_kill(&w, e)` | Destroy an entity and remove all its components |

### Spawning Entities

The most common pattern is `world_spawn_with`, which allocates an entity and attaches a component in one call:

```odin
ecs.world_spawn_with(&world, Food{col = 5, row = 10})
```

If an entity needs multiple components, spawn it first and then add them:

```odin
e := ecs.world_spawn(&world)
ecs.world_add_component(&world, e, Position{x = 100, y = 200})
ecs.world_add_component(&world, e, Velocity{x = 0, y = 50})
```

## Queries

Queries iterate all entities that have a given set of component types. The engine provides two styles:

### Typed Queries (Preferred)

Zero-allocation, type-safe iteration. Defined in `engine/ecs/query.odin`:

```odin
// Query all entities with a Food component
ecs.world_query1(&world, Food, nil, proc(e: ecs.Entity, food: ^Food, ctx: rawptr) {
    // food is a live pointer into the sparse set — mutations are immediate
})
```

Variants: `world_query1` (1 component), `world_query2` (2 components), `world_query3` (3 components). The smallest matching sparse set is iterated, with the others checked via sparse lookup — this minimizes wasted iterations.

### The `ctx: rawptr` Pattern

Odin does not support closures — proc literals cannot capture variables from their enclosing scope. The `ctx: rawptr` parameter exists to work around this. You pack any data the callback needs into a local struct, pass its address as `ctx`, and cast it back inside the callback:

```odin
data := struct { area: ^Playable_Area, dt: f32 }{ area, dt }

ecs.world_query1(&world, Snake, &data, proc(e: ecs.Entity, snake: ^Snake, raw: rawptr) {
    c := (^struct { area: ^Playable_Area, dt: f32 })(raw)
    // use c.area, c.dt
})
```

This is a C-style pattern. It works but requires careful casting. The struct type in the cast must exactly match the struct type passed in — there is no compiler check across the `rawptr` boundary.

### Legacy Query

`world_query` returns a `Query_Result` with a dynamic array of matching entity indices. This allocates on every call and exists for compatibility. Prefer the typed queries for all new code.

## Further Reading

- [Systems](systems.md) — How behavior is organized into phased systems
- [Snake Game Walkthrough](snake_game.md) — Concrete example of all these concepts in use
