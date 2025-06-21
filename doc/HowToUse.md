# RECS Guide

## Introduction

RECS is a reactive Entity-Component-System (ECS) framework in Julia, designed for high-performance game development and simulations. In an ECS, **entities** are objects, **components** store their data, and **systems** define their behavior. RECS stands out with its asynchronous, data-driven architecture, enabling modular and efficient workflows. This guide walks you through installing and using RECS to build your own ECS-based projects.

For a deeper understanding of RECS's architecture, see [A Reactive Architecture for ECS](link-to-main-article).

## Getting Started

To install RECS, use Julia's package manager:

```julia
julia> ]add RECS
```

For the development version, add the GitHub repository:

```julia
julia> ]add https://github.com/Gesee-y/RECS.jl.git
```

After installation, import RECS:

```julia
using RECS
```

## Creating Components

Components are data containers for entities, defined using the `@component` macro. Each component is a struct with fields representing properties.

```julia
@component Name begin
    field1::Type1
    field2::Type2
    # ...
    fieldn::TypeN
end
```

Example:

```julia
@component Position begin
    x::Float64
    y::Float64
end
```

This creates a `PositionComponent` with fields `x` and `y`. Initialize it with:

```julia
pos = PositionComponent(1.0, 2.5)
```

To change the default suffix (`Component`), overload `default_suffix`:

```julia
RECS.default_suffix() = "Object"

@component Position begin
    x::Float64
    y::Float64
end

pos = PositionObject(1.0, 2.5)
```

> **Note**: The component name (e.g., `Position`) is used for querying and accessing data, as shown later.

## Creating Systems

Systems process entities with specific components, defined using the `@system` macro.

```julia
@system MySystem
```

Initialize a system instance:

```julia
my_sys = MySystem()
```

> **Important**: Always store system instances, as RECS runs instances, not system types. Multiple instances of the same system can coexist.

## Running Systems

Systems process data via their `run!` function, called when relevant data is dispatched. Define `run!` to handle entity indices and components:

```julia
function RECS.run!(::MySystem, ref::WeakRef)
    indices = ref.value  # Indices of entities matching the system's subscription
    # Access components (see "Getting Components" below)
    # Process data
    return data  # Optional: return data for other systems via listen_to
end
```

> **Note**: `WeakRef` is a Julia feature that prevents unnecessary memory retention, reducing allocations.

Example system moving entities:

```julia
@system MoveSystem

function RECS.run!(::MoveSystem, ref::WeakRef)
    indices = ref.value
    positions = get_component(world, :Position)  # Get all Position components
    for idx in indices
        positions[idx].x += 0.1  # Move entity along x-axis
    end
    return positions  # Pass data to listeners
end
```

## Creating the ECS Manager

The `ECSManager` is the central coordinator, managing entities, components, and systems:

```julia
world = ECSManager()
```

## Subscribing to Archetypes

Systems subscribe to specific component combinations (archetypes) using `subscribe!`. An archetype is a group of entities sharing the same components.

```julia
subscribe!(world, my_sys, (PositionComponent,))
```

> **Tip**: Subscribe during initialization to minimize runtime overhead, as subscription scans existing entities (`O(n)` complexity).

## Creating Entities

Entities are rows in RECS’s internal table, with components as columns. Only specified components are initialized.

### With Initialized Components

Create an entity with pre-set components using keyword arguments:

```julia
entity = create_entity!(world; Position=PositionComponent(1.0, 2.0))
```

Ensure keyword names match component names (e.g., `Position` for `PositionComponent`).

### With Uninitialized Components

Faster, for entities with default or undefined component values:

```julia
entity = create_entity!(world, (PositionComponent,))
```

### Creating Multiple Entities

For bulk creation, use `request_entities` (fastest option):

```julia
entities = request_entities(world, 100, (PositionComponent,))
```

## Removing Entities

Mark an entity’s slot as available for reuse:

```julia
remove_entity!(world, entity)
```

> **Note**: Removed entities are not deleted but marked free, allowing new entities to override them.

## Getting Components

Access components efficiently using these methods.

### All Components

Retrieve a `StructArray` of all instances of a component (fast):

```julia
positions = get_component(world, :Position)  # Use symbol matching component name
```

### Entity’s Component

Access a specific entity’s component (slower, avoid for performance-critical code):

```julia
pos = entity.Position
```

For better performance, use:

```julia
positions = get_component(world, :Position)
pos = positions[get_id(entity)]
```

To modify a field, specify its type to avoid allocations:

```julia
positions = get_component(world, :Position)
x_positions::Vector{Float64} = positions.x  # Vector of x values
x_positions[get_id(entity)] = 5.0  # Modify x
```

> **Warning**: Omitting type annotations may cause slowdowns due to Julia’s type inference.

## Running Systems

Launch a system as an asynchronous task:

```julia
run_system!(my_sys)
```

Make a system listen to another’s output using `listen_to`:

```julia
listen_to(source_sys, listener_sys)
```

The listener’s `run!` receives the data returned by the source system. A system can listen to multiple sources.

## Dispatching Data

Trigger system execution:

```julia
dispatch_data(world)
```

To wait for all systems to complete:

```julia
blocker(world)
```

## Example: Complete Workflow

Here’s a minimal example combining components, systems, and entities:

```julia
using RECS

# Define component
@component Position begin
    x::Float64
    y::Float64
end

# Define system
@system MoveSystem

function RECS.run!(::MoveSystem, ref::WeakRef)
    indices = ref.value
    positions = get_component(world, :Position)
    for idx in indices
        positions[idx].x += 0.1
    end
    return positions
end

# Setup
world = ECSManager()
move_sys = MoveSystem()
subscribe!(world, move_sys, (PositionComponent,))
run_system!(move_sys)

# Create entity
entity = create_entity!(world; Position=PositionComponent(0.0, 0.0))

# Run for 3 frames
for frame in 1:3
    println("Frame $frame: x=$(entity.Position.x)")
    dispatch_data(world)
    blocker(world)
end
```

Output:
```
Frame 1: x=0.0
Frame 2: x=0.1
Frame 3: x=0.2
```

## Troubleshooting

- **Component not found**: Ensure the symbol in `get_component` matches the component name (e.g., `:Position` for `@component Position`).
- **System not running**: Verify subscription with `subscribe!` and data dispatch with `dispatch_data`.
- **Performance issues**: Use `get_component` instead of `entity.Component` and annotate types for field access.