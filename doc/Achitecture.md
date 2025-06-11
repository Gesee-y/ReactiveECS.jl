# An Event-Driven Architecture for ECS: Reconciling Performance and Modularity

---

## Introduction

Game engine development is often seen as a domain reserved for technical elites. Yet, at the core of every performant engine lies a fundamental element: **software architecture**.

Poor architecture inevitably leads to technical debt. A good one, on the other hand, ensures **longevity**, **modularity**, and **maintainability**. Among the dominant models, the **Entity-Component-System (ECS)** paradigm stands out. However, it is not without limitations.

In this article, I propose a hybrid variant: the **Event-Driven ECS (EDECS)**. This architecture retains the core principles of ECS while introducing a **reactive** model, based on system requirements, to streamline communication and improve entity processing.

> ⚠️ Not to be confused with an Event Bus or pub/sub system: here, the term "Event-Driven" refers to a **conditional and structured dispatch**, based on system subscriptions to component combinations.

---

## What is ECS?

The **Entity-Component-System (ECS)** is an architecture where game objects are represented by **entities**, uniquely identified. These entities are **structural only**: they have no behavior or logic.

Game logic is handled by **systems**, which operate on **components** attached to entities. Each system processes only the entities possessing a specific set of components.

Modern ECS frameworks often rely on the notion of **archetypes**: groupings of entities sharing the same component combination, allowing for optimized batch processing.

---

### Bitset Representation

A classical approach involves representing archetypes using bitsets. This allows for fast checks using bitwise operations:

```julia
archetype = 0b0011  # The entity has components 1 and 2
physic    = 0b0010  # The "Physic" system requires only component 2

if (archetype & physic == physic)
    # The entity is compatible with the Physic system
end
```

This method is performant but less scalable at large scale (binary limits, complex management). One can also use **dynamic queries**, but their cost is non-negligible.

---

## What is an Event-Driven ECS?

The **Event-Driven ECS (EDECS)** relies on a centralized architecture, where a **main manager (`ECSManager`)** groups entities by archetype.

Systems **subscribe** to the archetypes (in our implementation, it's internally represented by a bitset, speeding up matching) they're interested in. At each tick, the manager **dispatches** the matching entities to each system.

This model is based on three pillars:

* Structured entity storage,
* Targeted data distribution,
* Reactive, data-oriented processing.

---

### Example in Julia

```julia
using EDECS

const DELTA_TIME = 0.016

## Defining components
struct Health <: AbstractComponent
    hp::Int
end

EDECS.get_bits(::Type{Health})::UInt128 = 0b1

mutable struct TransformComponent <: AbstractComponent
    x::Float32
    y::Float32
end
Base.getindex(t::TransformComponent, i::Int) = i == 1 ? getfield(t, :x) : getfield(t, :y)
EDECS.get_bits(::Type{TransformComponent})::UInt128 = 0b10

mutable struct PhysicComponent <: AbstractComponent
    velocity::Float32
end
Base.getindex(p::PhysicComponent, i::Int) = getfield(p, :velocity)
EDECS.get_bits(::Type{PhysicComponent})::UInt128 = 0b100

EDECS.get_name(::Type{TransformComponent}) = :Transform
EDECS.get_name(::Type{PhysicComponent}) = :Physic

@system PhysicSystem
@system RenderSystem

function EDECS.run!(::PhysicSystem, tuple_data)
    component_data, entity_indices = tuple_data

    transforms = component_data[:Transform][2]  # Actual transform data
    physics = component_data[:Physics][2]       # Actual physics data
    
    transform_indices = entity_indices.data.Transform
    physics_indices = entity_indices.data.Physics
    
    # Apply physics to transforms
    for i in eachindex(transform_indices)
        transform_idx = transform_indices[i]
        physics_idx = physics_indices[i]
        
        transforms.x[transform_idx] += physics.velocity[physics_idx] * DELTA_TIME
    end
end

function EDECS.run!(::RenderSystem, tuple_data)
    component_data, entity_indices = tuple_data

    transforms = component_data[:Transform][2]
    transform_indices = entity_indices.data.Transform

    for i in eachindex(transform_indices)
        transform = transforms[i]
        println("Rendering entity at position ($(transform.x), $(transform.y))")
    end
end

ecs = ECSManager{BitArchetype}()

physic_sys = PhysicSystem()
render_sys = RenderSystem()

# We subscribe for a set of component
subscribe!(ecs, physic_sys, (TransformComponent, PhysicComponent))
listen_to(physic_sys,render_sys) # This will make the render system wait for the physic system to pass him data

# We define our Entities
e = Entity(BitArchetype,1; Health = Health(100), Transform = TransformComponent(1.0,2.0))
e2 = Entity(BitArchetype,2; Health = Health(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))

# We add them to our manager
add_entity!(ecs, e)
add_entity!(ecs, e2)

# We launch the system, it will be executed as an asynchronous task
run_system!(physic_sys)
run_system!(render_sys)

N = 3

for i in 1:N
    println("FRAME $i")
    dispatch_data(ecs) # We dispatch data to all the systems
    yield()
end
```

> **Note** : the function `listen_to` just add the system as a listener, the 2 system doesn't need each other. the listener (the last argument of the function) just wait passively for data (that may be coming from anyone) and the source just pass the results of his `run!` function to every system listening to him.

---

### Technical Overview

#### Dispatching Logic

The `ECSManager` acts as the central coordinator. It holds all components using a **Struct of Arrays (SoA)** layout for cache-friendly access patterns. When `dispatch_data` is called, the manager sends each subscribed system a **tuple of `WeakRef`s** to simplify memory handling and avoid unnecessary allocations.

* The **first element** is a `WeakRef` to a dictionary mapping component names (as defined by `get_name`) to their SoA data.
* The **second element** is a `WeakRef` to an `aSoA` (an associative Struct of Arrays), which maps each component name to a vector of indices. These indices reference the actual data within the SoA for entities that match the system's subscription.

This design avoids the need for optional components — systems technically have access to all registered components — but only the relevant subset is prefiltered and passed to them for iteration.

#### Subscription Logic

When a system subscribes to a set of components, the manager builds a dedicated index set containing only the entities that match this component combination. If another system has already subscribed to the same combination, the manager simply adds the new system to the existing subscription group.

The `subscribe!` function has a time complexity of **`O(n)`**, where `n` is the number of existing entities. Although it can be called at any time, **it is recommended to perform subscriptions during the engine's loading phase** to avoid runtime overhead.

#### System Execution

Calling `run_system!` starts the system in a blocking task, which suspends execution until the `ECSManager` dispatches the required data. Once unblocked, the system's `run!` function is invoked with its input data. Upon completion, the result is automatically forwarded to all systems registered as listeners via `listen_to`.

To prevent runtime issues, **cyclic dependencies between systems are detected recursively** during `listen_to` registration, and a warning is emitted if a cycle is found.

Then, the system listening to another one will be executed in their registration order.

If a system encounters an error during execution, it will raise an exception. Logging support for crashes will be added in the future. A crashed system can be restarted by simply calling `run_system!` again.

---

### Overview

```
          ┌───────────────┐
          │ ECSManager    │ # When dispatch_data is called, the ECSManager will distribute the reference
          │ (Archetypes)  │ # To the correct group of entities to the correct systems
          └─────┬─────────┘
                │
        ┌───────┼──────────────┐
        │       │              │
┌──────▼───┐ ┌──▼────────┐ ┌───▼─────────┐
│ Physic   │ │ Print     │ │ Render      │ # These subsystems are just waiting for data, nothing else
│ System   │ │ System    │ │ System      │
└────▼─────┘ └───────────┘ └─────────────┘
     |                           |
     |    sending the result     |
     |---------------------------|
```

---

## Benchmark

**Test configuration:**

* **CPU**: Intel Pentium T4400 @ 2.2 GHz
* **RAM**: 2 GB DDR3
* **OS**: Windows 10
* **Julia**: v1.10.3
* **Active threads**: 2

### Dispatch performance

| Number of Entities | Performance        |
| ------------------ | ------------------ |
| 128                | \~580 ns (2 alloc) |
| 256                | \~572 ns (2 alloc) |
| 512                | \~552 ns (2 alloc) |
| 1024               | \~565 ns (2 alloc) |
| 10k                | \~569 ns (2 alloc) |
| 100k               | \~575 ns (2 alloc) |

| Number of Systems  | Performance           |
| ------------------ | --------------------- |
| 2                  |  ~580 ns (2 alloc)    |
| 5                  |  ~1.9 μs (20 alloc)   |
| 10                 |  ~3.7 μs (40 alloc)   |
| 20                 |  ~7.3 μs (80 alloc)   |
| 50                 |  ~17.7 μs (200 alloc) |
| 100                |  ~34.9 μs (400 alloc) |
| 200                |  ~73.7 μs (800 alloc) |

> **Complexity**: `O(k)`, where `k` is the number of system subscriptions.

### Entity operations

* **Adding entity** : 12.5 μs (24 alloc)
* **Removing entity** : 60.7 μs (30 alloc)

> **Analysis**:
>
> * Adding an entity requires scanning all components to classify it in the ECSManager and matching against all archetypes: `O(n + k)`.
> * Removing is costlier due to swap removals from multiple SoA buffers and reference cleaning: also `O(n + k)` but with higher constant factors.

### Scalability test

On a benchmarked 400k entities under dual-system translation (e.g., Physic + Render) and achieved stable frame times under ~1 ms. With dispatch time at ~600 ns, overhead remains negligible, demonstrating the viability of this architecture at scale.

---

## Comparative Table

| Feature                   | EDECS                   | Bevy ECS         | Flecs           | EnTT           |
| ------------------------- | ----------------------- | ---------------- | --------------- | -------------- |
| Dispatch Strategy         | Event-driven            | Schedule-driven  | Staged queries  | Manual/sparse  |
| Entity Iteration          | By subscription         | By schedule      | By system query | By view        |
| Memory layout             | SoA (via StructArray)   | SoA              | SoA             | AoS/SoA hybrid |
| Dynamic system add/remove | Yes                     | Partial          | Yes             | Yes            |
| Reactive communication    | Yes (via `listen_to`)   | No               | No              | No             |
| Parallel execution        | User-controlled         | Scheduler-driven | Yes             | Manual         |
| Query caching             | Yes (bitset match)      | Yes              | Yes             | Yes            |
| Multi-threading model     | User-defined            | Built-in         | Built-in        | Manual         |
| Network-ready             | Yes (manager as server) | No               | Partial         | No             |
| Language                  | Julia                   | Rust             | C/C++           | C++            |

---

## Advantages of EDECS

* **Stable performance**: one dispatch per tick, no redundant queries.
* **Custom optimisation**: each system chooses how to parallelize or vectorize its own logic.
* **Dynamic extensibility**: systems can be added or removed at runtime.
* **Reactive logic**: `listen_to` allows composing systems without tight coupling.
* **Improved memory locality**: components stored in contiguous SoA layout.
* **Ready for distributed architecture**: ECSManager can be centralized for multiplayer or server-client architectures.

---

## Conclusion

EDECS overcomes classical ECS limitations by offering **better scalability**, **good stability**, **a reactive architecture**, and improved readiness for **parallel or distributed processing**.

This model has been implemented for my experimental game engine in Julia. It combines ECS simplicity with targeted dispatch reactivity, without sacrificing performance.

For technical questions or contributions, feel free to reach out.

---
