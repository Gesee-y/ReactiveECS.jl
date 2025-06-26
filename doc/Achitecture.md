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

## What is RECS?

**Reactive ECS (RECS)** is a high-performance ECS framework built in Julia, designed to combine the efficiency of data-oriented design with the flexibility of reactive programming. At its core, RECS uses a centralized **ECSManager** that stores entities in a **Struct of Arrays (SoA)** layout in a columnar way (entities are rows, components are columns), groups relevant indices by archetype, and dispatches them to subscribed systems.

### Core Principles
- **Structured Storage**: Entities are stored in a cache-friendly SoA layout.
- **Targeted Dispatch**: Systems receive only the data they need, minimizing overhead.
- **Reactive Processing**: Systems communicate via data pipelines, using `listen_to` for loose coupling.
- **Entity Pooling**: Reuses memory slots for fast entity creation/deletion.

### Key Features
- **Cache-efficient SoA**: Optimizes memory access for large-scale processing.
- **Dynamic Subscriptions**: Systems subscribe to specific component sets, updated at runtime.
- **Reactive Pipelines**: Systems can listen to others’ outputs, enabling flexible workflows.
- **Low Allocations**: Minimal memory overhead during dispatch and execution.
- **Runtime Extensibility**: Add, modify, or remove systems without code changes.
- **Advanced Event System**: Built on [Notifyers.jl](https://github.com/Gesee-y/Notifyers.jl), supporting merge, filtering, one-shot listeners, priorities, and more.
- **Hierarchical Relationships**: Managed via [NodeTree.jl](https://github.com/Gesee-y/NodeTree.jl), with BFS/DFS traversal.
- **Profiling Tools**: Built-in debugging and visualization for performance analysis.

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

@system PhysicSystem begin
    delta::Float32
end
@system RenderSystem

function RECS.run!(world, sys::PhysicSystem, data)
    E = world[sys] # Our data
    indices::Vector{Int} = data.value # The indices of the entities requested by the system
    L = length(indices)

    transforms = E.Transform # A struct array of transform components
    physics = E.Physic # A struct array of physic components

    x_pos = transforms.x # A vector of all the x fields of the transform components
    velo = physics.velocity
    dt::Float32 = sys.delta

    @inbounds for i in indices
        x_pos[i] += velo[i]*dt
    end

    return transforms # This data will be passed to the system listening to this one
end

function RECS.run!(world, ::RenderSystem, pos)
    for i in eachindex(pos)
        t = pos[i]
        println("Rendering entity at position ($(t.x), $(t.y))")
    end
end

physic_sys = PhysicSystem()
render_sys = RenderSystem()

ecs = ECSManager()

subscribe!(ecs, physic_sys, (TransformComponent, PhysicComponent))
listen_to(physic_sys,render_sys)

# Creating 4 entity
# We pass as keywork argument the component of the entity
create_entity!(ecs; Health = HealthComponent(100), Transform = TransformComponent(1.0,2.0))
e1 = create_entity!(ecs; Health = HealthComponent(150), Transform = TransformComponent(1.0,2.0))

# This entity will have e1 as parent
e2 = create_entity!(ecs,e1; Health = HealthComponent(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))
e3 = create_entity!(ecs; Health = HealthComponent(50), Transform = TransformComponent(-5.0,0.0), Physic = PhysicComponent(1.0))

# We launch the system. Internally, it's creating an asynchronous task
run_system!(physic_sys)
run_system!(render_sys)

N = 3

for i in 1:N
    println("FRAME $i")

    # We dispatch data and each system will execute his `run!` function
    dispatch_data(ecs)
    blocker(ecs) # Will make the process wait for all systems to finish
    yield()
    sleep(0.016)
end
```

> **Note** : the function `listen_to` just add the system as a listener, the 2 systems don't need each other. the listener (the last argument of the function) simply wait passively for data which can come from anyone, and the source just pass the results of his `run!` function to every system listening to him.

---

### Technical Overview

#### **Internal Storage**

Components are stored in a **Struct of Arrays (SoA)** layout. When a new component is added, its SoA resizes to match the size of others, ensuring consistent index mapping. When an entity is added, a new slot is created across all SoAs, and that index becomes the entity ID. Upon removal, the index is marked unused and removed from matching archetypes.

Unused slots remain undefined but reserved — enabling **fast pooling** and simple memory reuse.

```

        INTERNAL STORAGE
 _______________________________________________________
|   |     Health    |     Transform    |    Physic     |
|-------------------------------------------------------     
|   |      hp       |    x    |    y   |    velocity   |   
|-------------------------------------------------------
| 1 |      100      |   1.0   |   1.0  |      //       |
|-------------------------------------------------------
| 2 |      150      |   1.0   |   1.0  |      //       |
|-------------------------------------------------------
| 2 |      50       |  -5.0   |   1.0  |     1.0       |     
|-------------------------------------------------------
| 3 |      50       |  -5.0   |   1.0  |     1.0       |
|------------------------------------------------------|

If a system have subscribed to the archetype (Transform, Physic) for exanple, when the entity 1 is added, nothing happens
When the entity 2 is added, since it match the archetype, its index will be added the archetype's vector, so that we will directly dispatch it when needed instead of querying again
```

### Tree Layout

The hierarchy between entities is ensured via the package [NodeTree](https://github.com/Gesee-y/NodeTree.jl), adding support for BFS/DFS and other traversal utility using `RECS.BFS_search(ecs)` or `RECS.DFS_search(ecs)`
We can visualize that hierarchy with `print_tree(io, ecs)`

#### Example layout
```
ECSManager with 4 Nodes : 
    ├─Entity : "Entity 1"
    ├─Entity : "Entity 2"
    │   └─Entity : "Entity 3"
    └─Entity : "Entity 4"
```

### Dispatching Logic

The `ECSManager` acts as the central coordinator. It holds all components using a **Struct of Arrays (SoA)** layout for cache-friendly access patterns. When `dispatch_data` is called, the manager sends each subscribed system a **`WeakRef`** to simplify memory handling and avoid unnecessary allocations.

The `WeakRef` point to a  `Vector{Int}`,a vector of the requested entities's indices. These indices reference the actual data within the SoA for entities that match the system's subscription.

This design eliminates the need for explicitly optional components — systems technically have access to all registered components due to the sparse nature of the data's storage — but only the relevant subset is prefiltered and passed to them for iteration.

### Subscription Logic

When a system subscribes to a set of components, the manager builds a dedicated index set containing only the entities that match this component combination. If another system has already subscribed to the same combination, the manager simply adds the new system to the existing subscription group.

The `subscribe!` function has a time complexity of **`O(n)`**, where `n` is the number of existing entities. Although it can be called at any time, **it is recommended to perform subscriptions during the engine's loading phase** to avoid runtime overhead.

### System Execution

Calling `run_system!` starts the system in a blocking task, which suspends execution until the `ECSManager` dispatches the required data. Once unblocked, the system's `run!` function is invoked with its input data. Upon completion, the result is automatically forwarded to all systems registered as listeners via `listen_to`.

To prevent runtime issues, **cyclic dependencies between systems are detected recursively** during `listen_to` registration, and a warning is emitted if a cycle is found.

Then, the system listening to another one will be executed as asynchronous task so there is no enforced execution order. Instead, systems can be chained via listener relationships.

If a system encounters an error during execution, it will raise a warning that can be logged and the system's execution will be stopped. A crashed system can be restarted by simply calling `run_system!` again.

### Event system

ReactiveECS provide a fully functional event system. It leverage the [Notifyers.jl](https://github.com/Gesee-y/Notifyers.jl) package.
You can define a new package with `RECS.@Notifyer(arg1::T1, arg2::T2, ..., argn::Tn)`, see [Notifyers's doc](https://github.com/Gesee-y/Notifyers.jl/blob/main/docs/index.md). You can reuse all the features available in that package here. Meaning supports for:
- **Merge**: Combine multiple events (e.g., 10 HP changes into 1).
- **Filtering**: Calls listener just if the event meet some conditions.
- **One-shot Listeners**: Execute once and unsubscribe.
- **Priorities and Delays**: Control execution order and timing.
- **Retention**: Store recent event values.
- **Performance**: 200 ns (no listeners), 1.6 µs (per listener), 4 µs (in single task state, independent from the listeners's count).

### Debugging and profiling

We can switch to debug mode by overloading the function `debug_mode()`.
On this mode, the manager object will log the data received by each system, the data returned and profiling will be active
We can get the statistics of a system with `get_profile_stats(system)`. The format of the stats is the same as the one returned by `@timed`.
By default, the logs aren't directly written to a file. You should use `write!(io, ecs.logger)` where `ecs` is your `ECSManager` object.

---

### Overview

## **Execution Diagram**

```
    ┌───────────────┐
    │  ECSManager   │
    └─────┬─────────┘
          │ dispatch_data()
     ┌────┴────┬──────────┬
     │         │          │
    ┌▼────────┐┌▼─────────┐
    │ Physic  ││ Print    │
    │ System  ││ System   │
    └───┬─────┘└──────────┘
        │ Forward result
        └────────────┬────────────┐
                     ▼            ▼
                 RenderSystem  Other Listeners
```

---

## Benchmark

**Test configuration:**

* **CPU**: Intel Pentium T4400 @ 2.2 GHz
* **RAM**: 2 GB DDR3
* **OS**: Windows 10
* **Julia**: v1.10.5
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
| 2                  |  ~580 ns (1 alloc)    |
| 5                  |  ~1.3 μs (1 alloc)    |
| 10                 |  ~2.7 μs (1 alloc)    |
| 20                 |  ~5.3 μs (1 alloc)    |
| 50                 |  ~13.5 μs (1 alloc) |
| 100                |  ~26.1 μs (1 alloc) |
| 200                |  ~50.3 μs (1 alloc) |

> **Complexity**: `O(k)`, where `k` is the number of system subscriptions.

### Entity operations

* **Adding entity** : 869 ns (8 allocations: 896 bytes)
* **Removing entity** : 168 ns (1 allocations: 90 bytes)

> **Analysis**:
>
> * Adding an entity requires scanning all archetypes to classify it in the ECSManager and adding his components to the manager: `O(n + k)` where `n` is the number of archetype and k the number of components of the entity.
> * Removing is simpler, it just require to mark the index of the enity as free and remove his index from all the archetypes it belongs to. This operation is `O(k)` where `k` is the number of archetype the entity matched 

### Scalability test

On a benchmarked 100k entities under dual-system translation (e.g., Physic + Render) and achieved stable frame times under ~100 us. With dispatch time at ~600 ns, overhead remains negligible, demonstrating the viability of this architecture at scale.

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
| Create     4 entities with two Components | 1816ns    | 3155ns | 10119ns   | 2692ns     | 444861ns | 1315ns     | 4901ns     | 1150ns  |
| Create     8 entities with two Components | 2245ns    | 3461ns | 10313ns   | 3086ns     | 444572ns | 1426ns     | 5522ns     | 2104ns  |
| Create    16 entities with two Components | 2995ns    | 3812ns | 10869ns   | 3654ns     | 443523ns | 1555ns     | 6458ns     | 3850ns  |
| Create    32 entities with two Components | 4233ns    | 4419ns | 11265ns   | 4838ns     | 448326ns | 1875ns     | 8323ns     | 5366ns |
| Create    64 entities with two Components | 6848ns    | 5706ns | 12227ns   | 7042ns     | 467177ns | 2499ns     | 12369ns    | 8710ns |

|                                           | EntityX   | EnTT   | Ginseng   | mustache   | Flecs   | pico_ecs   | gaia-ecs   | RECS
|:------------------------------------------|:----------|:-------|:----------|:-----------|:--------|:-----------|:-----------|:--------|
| Create   256 entities with two Components | 21us      | 13us   | 16us      | 20us       | 535us   | 6us        | 36us       | 28us    | 
| Create   ~1K entities with two Components | 81us      | 42us   | 34us      | 73us       | 846us   | 21us       | 125us      | 105us   |
| Create   ~4K entities with two Components | 318us     | 161us  | 101us     | 283us      | 1958us  | 92us       | 481us      | 474us   |
| Create  ~16K entities with two Components | 1319us    | 623us  | 363us     | 1109us     | 6365us  | 366us      | 1924us     | 2874us  |

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

|                                        | EntityX   | EnTT   | Ginseng   | mustache   | Flecs   | pico_ecs   | gaia-ecs   | RECS     |
|:---------------------------------------|:----------|:-------|:----------|:-----------|:--------|:-----------|:-----------|:---------|
| Dispatch     1 entities with 2 systems | 29ns      | 16ns   | 7ns       | 36ns       | 577ns   | 16ns       | 53ns       | 560 ns   |
| Dispatch     4 entities with 2 systems | 75ns      | 45ns   | 28ns      | 126ns      | 1313ns  | 34ns       | 113ns      | 560 ns   |
| Dispatch     8 entities with 2 systems | 137ns     | 87ns   | 51ns      | 151ns      | 1475ns  | 55ns       | 133ns      | 560 ns   |
| Dispatch    16 entities with 2 systems | 266ns     | 145ns  | 94ns      | 190ns      | 1389ns  | 95ns       | 147ns      | 560 ns   |
| Dispatch    32 entities with 2 systems | 534ns     | 278ns  | 198ns     | 242ns      | 1467ns  | 194ns      | 191ns      | 560 ns   |
| Dispatch    64 entities with 2 systems | 1080ns    | 555ns  | 404ns     | 357ns      | 1583ns  | 353ns      | 300ns      | 560 ns   |

|                                        | EntityX   | EnTT   | Ginseng   | mustache   | Flecs   | pico_ecs   | gaia-ecs   | RECS     |
|:---------------------------------------|:----------|:-------|:----------|:-----------|:--------|:-----------|:-----------|:---------|
| Dispatch   256 entities with 2 systems | 4us       | 2us    | 1us       | 1us        | 2us     | 1us        | 1us        | 560 ns   |
| Dispatch   ~1K entities with 2 systems | 18us      | 8us    | 7us       | 3us        | 4us     | 7us        | 4us        | 560 ns   |
| Dispatch   ~4K entities with 2 systems | 82us      | 32us   | 28us      | 14us       | 15us    | 41us       | 15us       | 560 ns   |
| Dispatch  ~16K entities with 2 systems | 301us     | 145us  | 132us     | 56us       | 56us    | 165us      | 67us       | 560 ns   |

> **Analysis**
> The RECS is capable to achieve these performances due to preclassified data and the efficient use of pooling and sparse struct of arrays

---

## Advantages of RECS

- **High Performance**: Near-constant dispatch times (~580 ns) and vectorized updates (90 µs for 100k entities).
- **Improved memory locality**: components stored in contiguous SoA layout.
- **Stable performance**: one dispatch per tick, no redundant queries.
- **Reactive Design**: `listen_to` enables decoupled, dynamic system pipelines.
- **Flexible Events**: Merge, one-shot, and prioritized events enhance reactivity.
- **Scalability**: Efficient for 100k+ entities, with pooling and SoA.
- **Extensibility**: Add systems at runtime with minimal code changes.
- **Hierarchy Support**: `NodeTree.jl` provides robust parent-child relationships.
- **Profiling**: Built-in tools for debugging and optimization.
- **Ready for distributed architecture**: ECSManager can be centralized for multiplayer or server-client architectures.

## Actual limitation

- **Component access**: It doesn't meet the performances I wanted, still takes 400ns for a component modification
- **Asynchronous Complexity**: Reactive pipelines can be harder to debug, though mitigated by profiling tools.

---

## Conclusion

RECS overcomes classical ECS limitations by offering **better scalability**, **good stability**, **a reactive architecture**, and improved readiness for **parallel or distributed processing**.
This architecture is particularly suited for real-time simulation, 2D/3D games, and projects requiring dynamic reactivity without compromising performance.
This model has been implemented for my experimental game engine in Julia. It combines ECS simplicity with targeted dispatch reactivity, without sacrificing performance.

For technical questions or contributions, feel free to reach out.

