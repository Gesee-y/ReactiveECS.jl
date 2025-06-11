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

# The `ref` argument refer to a tuple with the following data `(WeakRef(dict_of_component_data), WeakRef(vector_of_component_idx))`
function EDECS.run!(::PhysicSystem, ref)
    ref1, ref2 = ref
    data = ref1.value # We get the dict of component data
    entities::aSoA = ref2.value # We get the set of index corresponding to this system
    pos::Vector{Int} = entities.data.Transform
    vel::Vector{Int} = entities.data.Physic
    
    # Leveraging `StructArray.jl`
    # This will return a contiguous vector of data
    x_pos::Vector{Float32} = data[:Transform][2].x # the `2` Refers to the actual data, the index `1` contain the corresponding entities
    velo::Vector{Float32} = data[:Physic][2].velocity

    # Then we use the the corresponding index
    # `pos` and `vel` always have the same length so you can do this without problem
    # You can vectorize the loop if you are sure that your data are contiguous
    # meaning your entities data follow themselves and you can use just a range or a `eachindex` to get them 
    for i in eachindex(pos)
        x_pos[pos[i]] += velo[vel[i]]
    end

    return ref # This will be passed to all the systems listening to this one (a system can even listen to himself)
end

function EDECS.run!(::RenderSystem, ref)
    data = ref[1].value
    pos = data[:Transform][2]
    for i in eachindex(pos)
        t = pos[i]
        println("Rendering entity at position ($(t.x), $(t.y))")
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
| 100k               | \~575 μs (2 alloc) |

> **Complexity**: `O(k)`, where `k` is the number of system subscriptions.

### Entity operations

* **Adding entity** : 12.5 μs (24 alloc)
* **Removing entity** : 60.7 μs (30 alloc)

> **Analysis**:
>
> * Adding an entity requires scanning all components to classify it in the ECSManager and matching against all archetypes: `O(n + k)`.
> * Removing is costlier due to swap removals from multiple SoA buffers and reference cleaning: also `O(n + k)` but with higher constant factors.

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
