# ReactiveECS Guide

## Introduction

ReactiveECS is a reactive Entity-Component-System (ECS) framework in Julia, designed for high-performance game development and simulations. In an ECS, **entities** are objects, **components** store their data, and **systems** define their behavior. ReactiveECS stands out with its asynchronous, data-driven architecture, enabling modular and efficient workflows. This guide walks you through installing and using ReactiveECS to build your own ECS-based projects.

For a deeper understanding of ReactiveECS's architecture, see [A Reactive Architecture for ECS](link-to-main-article).

## Getting Started

To install ReactiveECS, use Julia's package manager:

```julia
julia> ]add ReactiveECS
```

For the development version, add the GitHub repository:

```julia
julia> ]add https://github.com/Gesee-y/ReactiveECS.jl
```

After installation, import ReactiveECS:

```julia
using ReactiveECS
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

This creates a `Position` component with fields `x` and `y`. Initialize it with:

```julia
pos = Position(1.0, 2.5)
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

You can also create a system with custon fields with :

```julia
@system MySystem begin
    field1::Type1
    field2::Type2
    #...
    fieldn::Typen
end
```

and then you can initialize it with

```julia
my_sys = MySystem(n1,n2,...,nn)
```

> **Important**: Always store system instances, as RECS runs instances, not system types. Multiple instances of the same system can coexist, even with different queries.

## Running Systems

Systems process data via their `run!` function, called when relevant data is dispatched. Define `run!` to handle entity indices and components:

```julia
function ReactiveECS.run!(world, sys::MySystem, ref::WeakRef)
    query = ref.value  # Indices of entities matching the system's subscription
    # Access components (see "Getting Components" below)
    @foreachrange query begin
        for i in range
            # Your processing
        end
    end

    return # Optional: return data for other systems via listen_to
end
```

> **Note**: `WeakRef` is a Julia feature that prevents unnecessary memory retention, reducing allocations.

Example system moving entities:

```julia
@system MoveSystem begin
    dt::Float32

function ReactiveECS.run!(world, sys::MoveSystem, ref::WeakRef)
    query = ref.value
    positions = get_component(world, :Position)  # Get all Position components
    dt = sys.dt

    @foreachrange query begin
        for idx in range
            positions.x[idx] += dt  # Move entity along x-axis
        end
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
subscribe!(world, my_sys, @query(world, PositionComponent))
```

> **Tip**: Subscribe during initialization to minimize runtime overhead, as subscription scans existing entities (`O(n)` complexity).

## Creating Entities

Entities are rows in RECS’s internal table, with components as columns. Only specified components are initialized.

### With Initialized Components

Create an entity with pre-set components using keyword arguments:

```julia
entity = create_entity!(world; Position=Position(1.0, 2.0))
```

### With Uninitialized Components

Faster, for entities with default or undefined component values:

```julia
entity = create_entity!(world, (:Position,))
```

### Creating Multiple Entities

For bulk creation, use `request_entity!` (fastest option):

```julia
entities_init = request_entity!(world, 100; Position=Position(1.0,1.0))
entities = request_entity!(world, 100, (:Position,))
```

## Removing Entities

Mark an entity’s slot as available for reuse:

```julia
remove_entity!(world, entity)
```

> **Note**: Removed entities are not deleted but swapped with the last valid entity and placed outside the range, allowing new entities to override. If you create a new entity with no initialized component, it will have the data of that deleted entity.

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
x_positions = positions.x  # Vector of x values
x_positions[get_id(entity)] = 5.0  # Modify x
```

## Locking

You have the ability to lock a specific field while working to avoid race conditions on that fields.
for that you can do :

```
positions = get_component(world, :Position)
get_lock(position, (:x,)) # or get_lock(world, :Position, (:x,))
```

If the x field of position has sub fields you can also lock them if necessary by specifying their symbol after `:x`

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
using ReactiveECS

# Define component
@component Position begin
    x::Float64
    y::Float64
end

# Define system
@system MoveSystem begin
    dt::Float32

function ReactiveECS.run!(world, sys::MoveSystem, ref::WeakRef)
    query = ref.value
    positions = get_component(world, :Position)  # Get all Position components
    dt = sys.dt

    @foreachrange query begin
        for idx in range
            positions.x[idx] += dt  # Move entity along x-axis
        end
    end
    return positions  # Pass data to listeners
end

# Setup
world = ECSManager()
move_sys = MoveSystem(0.1)

subscribe!(world, move_sys, @query(world,Position))
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
