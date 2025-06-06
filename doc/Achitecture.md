## 📄 **An Event-Driven Architecture for ECS: Reconciling Performance and Modularity**

---

### Introduction

Game engine development is often seen as a domain reserved for technical elites. Yet, at the heart of every efficient engine lies a fundamental pillar: **software architecture**.

A poor architecture inevitably leads to technical debt. A good one, on the other hand, ensures **longevity**, **modularity**, and **maintainability**. Among prevailing models, the **Entity-Component-System (ECS)** paradigm has become standard—but it’s not without limitations.

In this article, I propose a hybrid variant: the **Event-Driven ECS (EDECS)**. This architecture retains the core principles of ECS while introducing a **reactive**, system-demand-driven model that streamlines communication and improves entity processing.

> ⚠️ Note: This is *not* an event bus or pub/sub system. The term “Event-Driven” here refers to a **structured, conditional dispatching model**, based on system subscriptions to component sets.

---

### What is ECS?

The **Entity-Component-System (ECS)** architecture represents game objects as **entities**, uniquely identified and structurally passive—they carry no behavior or logic.

Game logic is handled by **systems**, which operate on **components** attached to these entities. Each system processes only those entities that have a specific set of components.

Modern ECS architectures often use **archetypes**: groups of entities that share the same component layout, allowing for batched and optimized processing.

---

### Bitset Representation

A common approach is to represent archetypes using bitsets. This allows fast compatibility checks via bitwise logic:

```julia
archetype = 0b0011  # Entity has components 1 and 2
physic    = 0b0010  # The "Physic" system requires only component 2

if (archetype & physic == physic)
    # Entity is compatible with the Physic system
end
```

This method is performant, but not very scalable (due to binary limits and complex management). An alternative is **dynamic queries**, though they incur a higher runtime cost.

---

## What is an Event-Driven ECS?

The **Event-Driven ECS (EDECS)** relies on a centralized architecture where an **`ECSManager`** groups entities by archetype.

Systems **subscribe** to the archetypes they care about. At each tick, the manager **dispatches** the corresponding entities to each system.

This model is based on three principles:

* Structured storage of entities
* Targeted data distribution
* Reactive, data-oriented processing

---

### Julia Example

```julia
using EDECS

# Component definitions
struct Health <: AbstractComponent
    hp::Int
end

mutable struct TransformComponent <: AbstractComponent
    x::Float32
    y::Float32
end

struct PhysicComponent <: AbstractComponent
    velocity::Float32
end

# Component naming helpers
EDECS.get_name(::TransformComponent) = :Transform
EDECS.get_name(::PhysicComponent)    = :Physic

# Declare systems using macros
@system(PhysicSystem, Entity)
@system(PrintSystem, Entity)
@system(RenderSystem, Entity)

# Implement system behavior
function run!(::PhysicSystem, entities)
    for entity in entities
        t = entity.components[:Transform]
        v = entity.components[:Physic]
        t.x += v.velocity
    end
end

function run!(::PrintSystem, entities)
    for entity in entities
        println("Entity: $(entity.id)")
    end
end

function run!(::RenderSystem, entities)
    for entity in entities
        t = entity.components[:Transform]
        println("Rendering entity $(entity.id) at position ($(t.x), $(t.y))")
    end
end

# Initialize ECS manager
ecs = ECSManager{Entity}()

# Create two entities
e1 = Entity(1, Dict(:Health => Health(100), :Transform => TransformComponent(1.0, 2.0)))
e2 = Entity(2, Dict(:Health => Health(50), :Transform => TransformComponent(-5.0, 0.0), :Physic => PhysicComponent(1.0)))

add_entity!(ecs, e1)
add_entity!(ecs, e2)

# Initialize systems
print_sys   = PrintSystem()
physic_sys  = PhysicSystem()
render_sys  = RenderSystem()

# Subscribe systems to archetypes
subscribe!(ecs, print_sys,   (:Health, :Transform))
subscribe!(ecs, physic_sys,  (:Transform, :Physic))
subscribe!(ecs, render_sys,  (:Transform,))

# Launch systems asynchronously
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

## EDECS Benchmark

This benchmark measures the performance of **dispatching only**, as it's the core logic, independent of game-specific code.

**Test Configuration:**

* **CPU**: Intel Pentium T4400 @ 2.2 GHz
* **RAM**: 2 GB DDR3
* **OS**: Windows 10
* **Julia**: v1.10.3
* **Active threads**: 2

**Scenario:**

* 3 components (Health, Transform, Physic)
* 3 active systems
* Varying chunk sizes

| Entity Count | 64 obj/chunk         | 128 obj/chunk       | 256 obj/chunk       | 512 obj/chunk       |
| ------------ | -------------------- | ------------------- | ------------------- | ------------------- |
| 128          | 0.031 ms (18 alloc)  | 0.032 ms (12 alloc) | 0.037 ms (6 alloc)  | 0.040 ms (6 alloc)  |
| 256          | 0.057 ms (30 alloc)  | 0.056 ms (18 alloc) | 0.040 ms (12 alloc) | 0.032 ms (6 alloc)  |
| 512          | 0.069 ms (54 alloc)  | 0.054 ms (30 alloc) | 0.053 ms (18 alloc) | 0.052 ms (12 alloc) |
| 1024         | 0.094 ms (102 alloc) | 0.059 ms (54 alloc) | 0.068 ms (30 alloc) | 0.046 ms (18 alloc) |

> ✅ **Analysis**:
>
> * Chunks that are too small increase allocations and degrade performance.
> * Larger chunks reduce dispatch cost but are harder to parallelize.
> * **Best trade-off**: 128–256 entities per chunk.
> * **Tip**: use **pooling** and dynamically adapt chunk size to hardware.

---

## Benefits of an Event-Driven ECS

* **Consistent performance**: only one dispatch per tick, no repeated queries.
* **Parallelism-friendly**: chunks can be processed across threads.
* **Dynamic extensibility**: systems can be hot-swapped at runtime.
* **Network-ready**: a server can act as the central ECSManager distributing entities to clients.
* **Improved memory locality**: archetype grouping enables cache-friendly access.

---

## Conclusion

EDECS addresses the classic limitations of ECS by offering better **scalability**, a **reactive architecture**, and better support for **parallel or distributed processing**.

This model was implemented for experimental game engine in Julia which may be released soon. It merges ECS simplicity with the reactivity of targeted dispatching—without compromising on performance.
