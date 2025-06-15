# A Reactive Architecture for ECS: Reconciling Performance and Modularity

---

## Introduction

Game engine development is often perceived as an expert-only domain. Yet, beneath every performant engine lies a single unifying force: **software architecture**.

A poor architecture inevitably leads to technical debt. A good one ensures **modularity**, **maintainability**, and **scalability** over time. Among the leading paradigms, the **Entity-Component-System (ECS)** stands out for its data-oriented design. However, ECS comes with its own set of trade-offs — especially regarding communication between systems and runtime flexibility.

This article introduces **Reactive ECS (RECS)** — a hybrid architecture that combines the performance of ECS with the **reactivity and decoupling** of event-driven models. RECS aims to preserve ECS’s cache efficiency while offering a more declarative and composable system pipeline.


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

## What is a Reactive ECS?

The **Reactive ECS (RECS)** relies on a centralized architecture, where a **main manager (`ECSManager`)** keep enetities in a giant table where the columns are components and the rows entities, then the main system groups entities's id by archetype.

Systems **subscribe** to the archetypes (in our implementation, it's internally represented by a bitset, speeding up matching) they're interested in. At each tick, the manager **dispatches** the matching entities to each system.
This model is based on four pillars:

* Structured entity storage,
* Targeted data distribution,
* Reactive, data-oriented processing.
* Entity pooling

### **Key Features:**

* Efficient, cache-friendly **SoA component layout**
* Subscription-based **entity filtering**
* **Data-pipelining** between systems via reactive listeners
* Minimal allocations, lightweight dispatching
* Built-in support for **entity pooling**

---

### Example in Julia

```julia
using RECS

# This will create a new component
# And set boilerplates for us
# The constructor is just the name passed here plus the suffix "Component"
@component Health begin
    hp::Int
end

@component Transform begin
    x::Float32
    y::Float32
end

@component Physic begin
    velocity::Float32
end

# We create a system
@system PhysicSystem
@system RenderSystem

# The system internal logic
# Each system should have one
function RECS.run!(::PhysicSystem, data)
    components = data[1].value # This contains all the components
    indices = data[2].value # This contains the index of the entities requested

    # We get ne necessary components
    transform_data = components[:Transform]
    physic_data = components[:Physic]

    # This is optimization is optional.
    # We could have just iterated on indices instead of creating these temporary views
    x_pos = view(transform_data.x, indices)
    velo = view(physic_data.velocity, indices)

    for i in eachindex(indices)
        x_pos[i] += velo[i]
    end

    return transform_data
end

function RECS.run!(::RenderSystem, pos) # Here `pos` is the transform_data we returned in the PhysicSystem `run!`
    for i in eachindex(pos)
        t = pos[i]
        println("Rendering entity at position ($(t.x), $(t.y))")
    end
end

ecs = ECSManager()

physic_sys = PhysicSystem()
render_sys = RenderSystem()

subscribe!(ecs, physic_sys, (TransformComponent, PhysicComponent))
listen_to(physic_sys,render_sys)

# Creating 3 entity
# We pass as keywork argument the component of the entity
e1 = create_entity!(ecs; Health = HealthComponent(100), Transform = TransformComponent(1.0,2.0))
e2 = create_entity!(ecs; Health = HealthComponent(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))
e3 = create_entity!(ecs; Health = HealthComponent(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))

# We launch the system. Internally, it's creating an asynchronous task
run_system!(physic_sys)
run_system!(render_sys)

N = 3

for i in 1:N
    println("FRAME $i")

    # We dispatch data and each system will execute his `run!` function
    dispatch_data(ecs)
    yield()
    sleep(0.016)
end
```

> **Note** : the function `listen_to` just add the system as a listener, the 2 systems don't need each other. the listener (the last argument of the function) simply wait passively for data which can come from anyone, and the source just pass the results of his `run!` function to every system listening to him.

---

### Technical Overview

### **Internal Storage**

Components are stored in a **Struct of Arrays (SoA)** layout. When a new component is added, its SoA resizes to match the size of others, ensuring consistent index mapping. When an entity is added, a new slot is created across all SoAs, and that index becomes the entity ID. Upon removal, the index is marked unused and removed from matching archetypes.

Unused slots remain undefined but reserved — enabling **fast pooling** and simple memory reuse.

```

        INTERNAL STORAGE
 _______________________________________________________
|   |     Health    |     Transform    |    Physic     |
|-------------------------------------------------------     
|   |      hp       |    x    |    y   |    velocity   |   
|-------------------------------------------------------
| 1 |      50       |   1.0   |   1.0  |      //       |
|-------------------------------------------------------
| 2 |      50       |  -5.0   |   1.0  |     1.0       |     
|-------------------------------------------------------
| 3 |      50       |  -5.0   |   1.0  |     1.0       |
|------------------------------------------------------|

If a system have subscribed to the archetype (Transform, Physic), when the entity 1 is added, nothing happens
When the entity 2 is added, since it match the archetype, its index will be added to vector, so that we will directly dispatch him when needed instead of querying again
```
#### Dispatching Logic

The `ECSManager` acts as the central coordinator. It holds all components using a **Struct of Arrays (SoA)** layout for cache-friendly access patterns. When `dispatch_data` is called, the manager sends each subscribed system a **tuple of `WeakRef`s** to simplify memory handling and avoid unnecessary allocations.

* The **first element** is a `WeakRef` to a dictionary mapping component names (as defined in `@component`) to their SoA data.
* The **second element** is a `WeakRef` to an `Vector{Int}`,a vector of the requested entities's indices. These indices reference the actual data within the SoA for entities that match the system's subscription.

This design eliminates the need for explicitly optional components — systems technically have access to all registered components due to the sparse nature of the data's storage — but only the relevant subset is prefiltered and passed to them for iteration.

#### Subscription Logic

When a system subscribes to a set of components, the manager builds a dedicated index set containing only the entities that match this component combination. If another system has already subscribed to the same combination, the manager simply adds the new system to the existing subscription group.

The `subscribe!` function has a time complexity of **`O(n)`**, where `n` is the number of existing entities. Although it can be called at any time, **it is recommended to perform subscriptions during the engine's loading phase** to avoid runtime overhead.

#### System Execution

Calling `run_system!` starts the system in a blocking task, which suspends execution until the `ECSManager` dispatches the required data. Once unblocked, the system's `run!` function is invoked with its input data. Upon completion, the result is automatically forwarded to all systems registered as listeners via `listen_to`.

To prevent runtime issues, **cyclic dependencies between systems are detected recursively** during `listen_to` registration, and a warning is emitted if a cycle is found.

Then, the system listening to another one will be executed as asynchronous task so there is no enforced execution order. Instead, systems can be chained via listener relationships.

If a system encounters an error during execution, it will raise a warning that can be logged and the system's execution will be stopped. A crashed system can be restarted by simply calling `run_system!` again.

---

### Overview

## **Execution Diagram**

```
          ┌───────────────┐
          │  ECSManager   │
          └─────┬─────────┘
                │ dispatch_data()
        ┌───────┼──────────────┐
        │       │              │
┌──────▼───┐ ┌──▼────────┐ ┌───▼─────────┐
│ Physic   │ │ Print     │ │ Render      │
│ System   │ │ System    │ │ System      │
└────▼─────┘ └───────────┘ └─────────────┘
     |                           |
     |      Forward result       |
     └────────────┬──────────────┘
                  ▼
         Systems listening for output
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

* **Adding entity** : 869 ns (8 allocations: 896 bytes)
* **Removing entity** : 168 ns (1 allocations: 90 bytes)

> **Analysis**:
>
> * Adding an entity requires scanning all archetypes to classify it in the ECSManager and adding his components to the manager: `O(n + k)` where `n` is the number of archetype and k the number of components of the entity.
> * Removing is simpler, it just require to mark the index of the enity as free and remove his index from all the archetypes it belongs to. This operation is `O(k)` where `k` is the number of archetype the entity matched 

### Scalability test

On a benchmarked 400k entities under dual-system translation (e.g., Physic + Render) and achieved stable frame times under ~1 ms. With dispatch time at ~600 ns, overhead remains negligible, demonstrating the viability of this architecture at scale.

---

## Comparative Table

> *Note*: The benchmark for the other engine hasn't been done by me. The characteristic of that person's machine is :

* **OS:** Linux 64-Bit (Kernel: 6.10.4)
* **CPU:** 3.13GHz @ 12Cores
* **RAM:** 47GB
* **Compiler:** gcc (GCC) 14.2.1

> While mine is :

* **OS**: Windows 10
* **CPU**: Intel Pentium T4400 @ 2.2 GHz
* **RAM**: 2 GB DDR3
* **Julia**: v1.10.3

### Creating Entities

|                                           | EntityX   | EnTT   | Ginseng   | mustache   | Flecs    | pico_ecs   | gaia-ecs   | RECS    |
|:------------------------------------------|:----------|:-------|:----------|:-----------|:---------|:-----------|:-----------|:--------|
| Create     1 entities with two Components | 1368ns    | 2881ns | 10449ns   | 2327ns     | 439949ns | 1331ns     | 4683ns     | 862ns   |
| Create     4 entities with two Components | 1816ns    | 3155ns | 10119ns   | 2692ns     | 444861ns | 1315ns     | 4901ns     | 2412ns  |
| Create     8 entities with two Components | 2245ns    | 3461ns | 10313ns   | 3086ns     | 444572ns | 1426ns     | 5522ns     | 4433ns |
| Create    16 entities with two Components | 2995ns    | 3812ns | 10869ns   | 3654ns     | 443523ns | 1555ns     | 6458ns     | 6921ns  |
| Create    32 entities with two Components | 4233ns    | 4419ns | 11265ns   | 4838ns     | 448326ns | 1875ns     | 8323ns     | 12598ns |
| Create    64 entities with two Components | 6848ns    | 5706ns | 12227ns   | 7042ns     | 467177ns | 2499ns     | 12369ns    | 21931ns |

|                                           | EntityX   | EnTT   | Ginseng   | mustache   | Flecs   | pico_ecs   | gaia-ecs   | RECS
|:------------------------------------------|:----------|:-------|:----------|:-----------|:--------|:-----------|:-----------|:---------|
| Create   256 entities with two Components | 21us      | 13us   | 16us      | 20us       | 535us   | 6us        | 36us       | 60us     | 
| Create   ~1K entities with two Components | 81us      | 42us   | 34us      | 73us       | 846us   | 21us       | 125us      | 347us    |
| Create   ~4K entities with two Components | 318us     | 161us  | 101us     | 283us      | 1958us  | 92us       | 481us      | 1256us   |
| Create  ~16K entities with two Components | 1319us    | 623us  | 363us     | 1109us     | 6365us  | 366us      | 1924us     | 4518us   |

### Destroying Entities

|                                            | EntityX   | EnTT   | Ginseng   | Flecs    | pico_ecs   | gaia-ecs   | RECS     |
|:-------------------------------------------|:----------|:-------|:----------|:---------|:-----------|:-----------|:---------|
| Destroy     1 entities with two components | 1008ns    | 904ns  | 1056ns    | 364035ns | 1208ns     | 3074ns     | 168ns    |
| Destroy     4 entities with two components | 1236ns    | 1028ns | 1419ns    | 363733ns | 1241ns     | 3355ns     | 668ns    |
| Destroy     8 entities with two components | 1366ns    | 1196ns | 1975ns    | 381173ns | 1267ns     | 3751ns     | 1426ns   |
| Destroy    16 entities with two components | 1660ns    | 1502ns | 2793ns    | 371021ns | 1320ns     | 4752ns     | 2688ns   |
| Destroy    32 entities with two components | 2394ns    | 2139ns | 4419ns    | 377250ns | 1438ns     | 6833ns     | 5312ns   |
| Destroy    64 entities with two components | 3815ns    | 3372ns | 7731ns    | 376331ns | 1644ns     | 10905ns    | 10752ns  |

|                                            | EntityX   | EnTT   | Ginseng   | Flecs   | pico_ecs   | gaia-ecs   | RECS      |
|:-------------------------------------------|:----------|:-------|:----------|:--------|:-----------|:-----------|:----------|
| Destroy   256 entities with two components | 12us      | 11us   | 28us      | 383us   | 2us        | 32us       | 43us      |
| Destroy   ~1K entities with two components | 48us      | 40us   | 105us     | 415us   | 8us        | 121us      | 168us     |
| Destroy   ~4K entities with two components | 201us     | 157us  | 434us     | 590us   | 32us       | 487us      | 627us     |
| Destroy  ~16K entities with two components | 812us     | 627us  | 1743us    | 1243us  | 122us      | 2038us     | 2688us    |

> **Analysis**
> *Adding entities* just consist of resizing the big table of data for one more entry, which may be costly, so in these benchmark, we batched it and we resized in one run instead of one at a time.
> *Removing entities* just consist of marking the entity's index as available and when creating a new entity, he will override the old one.
It also remove the entity in the vector of index of the archetype they matched.

### Updating System

|                                      | EntityX   | EnTT   | Ginseng   | mustache   | Flecs   | pico_ecs   | gaia-ecs   | RECS     |
|:-------------------------------------|:----------|:-------|:----------|:-----------|:--------|:-----------|:-----------|:---------|
| Update     1 entities with 2 systems | 29ns      | 16ns   | 7ns       | 36ns       | 577ns   | 16ns       | 53ns       | 560 ns   |
| Update     4 entities with 2 systems | 75ns      | 45ns   | 28ns      | 126ns      | 1313ns  | 34ns       | 113ns      | 560 ns   |
| Update     8 entities with 2 systems | 137ns     | 87ns   | 51ns      | 151ns      | 1475ns  | 55ns       | 133ns      | 560 ns   |
| Update    16 entities with 2 systems | 266ns     | 145ns  | 94ns      | 190ns      | 1389ns  | 95ns       | 147ns      | 560 ns   |
| Update    32 entities with 2 systems | 534ns     | 278ns  | 198ns     | 242ns      | 1467ns  | 194ns      | 191ns      | 560 ns   |
| Update    64 entities with 2 systems | 1080ns    | 555ns  | 404ns     | 357ns      | 1583ns  | 353ns      | 300ns      | 560 ns   |

|                                      | EntityX   | EnTT   | Ginseng   | mustache   | Flecs   | pico_ecs   | gaia-ecs   | RECS     |
|:-------------------------------------|:----------|:-------|:----------|:-----------|:--------|:-----------|:-----------|:---------|
| Update   256 entities with 2 systems | 4us       | 2us    | 1us       | 1us        | 2us     | 1us        | 1us        | 560 ns   |
| Update   ~1K entities with 2 systems | 18us      | 8us    | 7us       | 3us        | 4us     | 7us        | 4us        | 560 ns   |
| Update   ~4K entities with 2 systems | 82us      | 32us   | 28us      | 14us       | 15us    | 41us       | 15us       | 560 ns   |
| Update  ~16K entities with 2 systems | 301us     | 145us  | 132us     | 56us       | 56us    | 165us      | 67us       | 560 ns   |

> **Analysis**
> The RECS is capable to achieve these performances due to preclassified data and the efficient use of pooling and sparse struct of arrays

---

## Advantages of RECS

* **Stable performance**: one dispatch per tick, no redundant queries.
* **Custom optimisation**: each system chooses how to parallelize or vectorize its own logic.
* **Dynamic extensibility**: systems can be added or removed at runtime.
* **Reactive logic**: `listen_to` allows composing systems without tight coupling.
* **Improved memory locality**: components stored in contiguous SoA layout.
* **Ready for distributed architecture**: ECSManager can be centralized for multiplayer or server-client architectures.

## Actual limitation

* **Hard to profile**: The asynchronous nature of the architecture make it harder to use, debug and monitor

---

## Conclusion

RECS overcomes classical ECS limitations by offering **better scalability**, **good stability**, **a reactive architecture**, and improved readiness for **parallel or distributed processing**.
This architecture is particularly suited for real-time simulation, 2D/3D games, and projects requiring dynamic reactivity without compromising performance.
This model has been implemented for my experimental game engine in Julia. It combines ECS simplicity with targeted dispatch reactivity, without sacrificing performance.

For technical questions or contributions, feel free to reach out.

https://claude.ai/public/artifacts/a3ed064e-673d-407b-9cbf-9797546fae06

---

Voici la version corrigée de ton article avec les fautes d’anglais rectifiées, sans altérer ton style ou les termes techniques. Les corrections portent sur la grammaire, la conjugaison, la ponctuation et la précision lexicale. Je te fournis la version complète corrigée :

---
