## 📄 **An Event-Driven Architecture for ECS: Reconciling Performance and Modularity**

---

### Introduction

Game engine development is often seen as a domain reserved for technical elites. Yet, at the core of every performant engine lies a fundamental element: **software architecture**.

Poor architecture inevitably leads to technical debt. A good one, on the other hand, ensures **longevity**, **modularity**, and **maintainability**. Among the dominant models, the **Entity-Component-System (ECS)** paradigm stands out. However, it is not without limitations.

In this article, I propose a hybrid variant: the **Event-Driven ECS (EDECS)**. This architecture retains the core principles of ECS while introducing a **reactive** model, based on system requirements, to streamline communication and improve entity processing.

> ⚠️ Not to be confused with an Event Bus or pub/sub system: here, the term "Event-Driven" refers to a **conditional and structured dispatch**, based on system subscriptions to component combinations.

---

### What is ECS?

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

Systems **subscribe** to the archetypes they're interested in. At each tick, the manager **dispatches** the matching entities to each system.

This model is based on three pillars:

* Structured entity storage,
* Targeted data distribution,
* Reactive, data-oriented processing.

---

### Example in Julia

```julia
using EDECS

# Component definitions
struct Health <: AbstractComponent
	hp::Int
end
EDECS.get_bits(::Type{Health})::UInt128 = 0b1

mutable struct TransformComponent <: AbstractComponent
    x::Float32
    y::Float32
end
EDECS.get_bits(::Type{TransformComponent})::UInt128 = 0b10

struct PhysicComponent <: AbstractComponent
    velocity::Float32
end
EDECS.get_bits(::Type{PhysicComponent})::UInt128 = 0b100

# Naming helper for components
EDECS.get_name(::TransformComponent) = :Transform
EDECS.get_name(::PhysicComponent)    = :Physic

# System declarations via macro
@system(PhysicSystem, Entity)
@system(PrintSystem, Entity)
@system(RenderSystem, Entity)

# System behavior implementations
function run!(::PhysicSystem, ref::WeakRef)
	entities = ref.value
	for i in eachindex(entities)
		entity = validate(ref, i)
	    t = entity.components[:Transform]
	    v = entity.components[:Physic]
	    t.x += v.velocity
    end

    return ref
end

function run!(sys::PrintSystem, ref::WeakRef)
	entities = ref.value
	for i in eachindex(entities)
		entity = validate(ref, i)
		id = entity.id
		println("Entity: $id")
	end
end

function run!(::RenderSystem, ref)
    entities = ref.value
    for i in eachindex(entities)
		entity = validate(ref, i)
	    t = entity.components[:Transform]
	    println("Rendering entity $(entity.id) at position ($(t.x), $(t.y))")
	end
end


# ECS manager initialization
ecs = ECSManager{Entity}()

# Create two entities
e1 = Entity(1; Health = Health(100), Transform = TransformComponent(1.0,2.0))
e2 = Entity(2; Health = Health(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))

add_entity!(ecs, e1)
add_entity!(ecs, e2)

# System instances
print_sys   = PrintSystem()
physic_sys  = PhysicSystem()
render_sys  = RenderSystem()

# Subscribe to archetypes
subscribe!(ecs, print_sys,   (:Health, :Transform))
subscribe!(ecs, physic_sys,  (:Transform, :Physic))
listen_to(physic_sys, render_sys)

# Launch systems (asynchronous task)
run_system!(print_sys)
run_system!(physic_sys)
run_system!(render_sys)

# Simulate 3 frames
for i in 1:3
    println("FRAME $i")
    dispatch_data(ecs)
    yield()
end
```

---

## Overview

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
└──────────┘ └───────────┘ └─────────────┘
```

---

## EDECS Benchmark

Here, we measure only the performance of **dispatch**, as it's the core function, independent of business logic.

**Test configuration:**

* **CPU**: Intel Pentium T4400 @ 2.2 GHz
* **RAM**: 2 GB DDR3
* **OS**: Windows 10
* **Julia**: v1.10.3
* **Active threads**: 2

**Scenario:**

* 3 components (Health, Transform, Physic)
* 3 active systems
* Varying number of entities

| Number of Entities | Performance        |
| ------------------ | ------------------ |
| 128                | 0.002 ms (6 alloc) |
| 256                | 0.002 ms (6 alloc) |
| 512                | 0.002 ms (6 alloc) |
| 1024               | 0.002 ms (6 alloc) |

> ✅ **Analysis**:
> The number of entities does not affect performance. This is because dispatch is only dependent on the number of subscriptions and systems. The function has complexity O(n × m), where *n* is the number of archetypes and *m* is the number of systems.
> The number of allocations is constant because the manager pre-classifies the entities and, during dispatch, distributes only **references** to the system-specific arrays of matching entities.

---

## Advantages of an Event-Driven ECS

* **Stable performance**: one dispatch per tick, no redundant queries.
* **Custom parallelism**: each system chooses how to parallelize its own logic.
* **Dynamic extensibility**: systems can be added or removed at runtime.
* **Native network compatibility**: a server can act as a central manager, distributing entities to clients.
* **Improved memory locality**: grouping by archetype promotes cache-friendly access.

---

## Conclusion

EDECS overcomes classical ECS limitations by offering **better scalability**, a **reactive architecture**, and improved readiness for **parallel or distributed processing**.

This model has been implemented in my experimental engine in Julia. It combines ECS simplicity with targeted dispatch reactivity, without sacrificing performance.

For technical questions, feel free to reach out.

---
