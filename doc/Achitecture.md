# A Reactive Architecture for ECS: Reconciling Performance and Modularity

---

## Introduction

Game engine development is often perceived as an expert-only domain. Yet, beneath every performant engine lies a single unifying force: **software architecture**.

A poor architecture inevitably leads to technical debt. A good one ensures **modularity**, **maintainability**, and **scalability** over time. Among the leading paradigms, the **Entity-Component-System (ECS)** stands out for its data-oriented design. However, ECS comes with its own set of trade-offs — especially regarding communication between systems ,runtime flexibility and the usual iteration speed vs mutations costs.

This article introduces **Reactive ECS (RECS)**, an hybrid architecture that combines the performance of ECS with the **reactivity and decoupling** of event-driven models while providing the **memory locality** of archetypebased ECS but with lower **mutations costs***. RECS aims to preserve ECS’s cache efficiency while offering a more declarative and composable system pipeline.

---

## What is ECS?

The **Entity-Component-System (ECS)** is an architecture where game objects are represented by **entities**, uniquely identified. These entities are **structural only**: they have no behavior or logic.

Game logic is handled by **systems**, which operate on **components** attached to entities. Each system processes only the entities possessing a specific set of components.

Modern ECS frameworks often rely on the notion of **archetypes**: groupings of entities sharing the same component combination, allowing for optimized batch processing.

---

### Type of ECS

#### Archetype ECS

An **archetype ECS** is an implementation of the ECS where entities with the same set of components is stored in the same table. This table is called an **archetype**. Since entities are homogeneously stored and tightly packed in memory, this approach offers high queries and iteration performances but at the cost of slower **structural changes** such as adding/removing an entity or a component from an entity.

#### Sparse-set ECS

A **sparse set ECS** is an approach where every type of component has his own **sparse set**, then each entity has an entry at his ID in the sparse set of the components it have. This offers fast structural changes but iterations speed and memory locality are greatly reduced.

---

## What is RECS?

**Reactive ECS (RECS)** is a high-performance ECS framework built in Julia, designed to combine the efficiency of data-oriented design with the flexibility of reactive programming. At its core, RECS uses a centralized **ECSManager** that stores entities in a columnar way (entities are rows, components are columns), represent archetypes with **partitions**, use query to get the relevant partitions and dispatches them to subscribed systems.

### Core Principles
- **Structured Storage**: Entities are stored in a partitioned cache-friendly layout.
- **Targeted Dispatch**: Systems receive only the data they need, minimizing overhead.
- **Reactive Processing**: Systems communicate via data pipelines, using `listen_to` for loose coupling.
- **Entity Pooling**: Reuses memory slots for fast entity creation/deletion.

### Key Features

- **Cache-efficient SoA**: Optimizes memory access for large-scale processing.
- **Dynamic Subscriptions**: Systems subscribe to a query, which may change at runtime.
- **Reactive Pipelines**: Systems can listen to others’ outputs, enabling flexible workflows.
- **Runtime Extensibility**: Add, modify, or remove systems without code changes.
- **Advanced Event System**: Built on [Notifyers.jl](https://github.com/Gesee-y/Notifyers.jl), supporting merge, filtering, one-shot listeners, priorities, and more.
- **Profiling Tools**: Built-in debugging and visualization for performance analysis.

---

### Example in Julia

```julia
using ReactiveECS

# This will create a new component
# And set boilerplates for us
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

function ReactiveECS.run!(world, sys::Physic, ref::WeakRef)
    query = ref.value
    transforms = get_component(world, :Transforms)  # Get all Position components
    physics = get_component(world, :Physic)

    dt = sys.dt

    @foreachrange query begin
        pblock = get_block(transforms, range)
        vblock = get_block(physics, range)
        r = offset(range, get_offset(transforms, range))
        for i in r
            pos = pblock[i]
            vel = vblock[i]
            pblock[i] = Position(pos.x + vel.velocity*dt, pos.y) # Move entity along x-axis
        end
    end
    return transforms  # Pass data to listeners
end

function ReactiveECS.run!(world, ::RenderSystem, pos)
    for t in pos
        println("Rendering entity at position ($(t.x), $(t.y))")
    end
end


# Setup
world = ECSManager()
physic_sys = PhysicSystem()
render_sys = RenderSystem()

# This entity will have e1 as parent
e2 = create_entity!(world; Health = Health(50), Transform = Transform(-5.0,0.0), Physic = Physic(1.0))
e3 = create_entity!(world; Health = Health(50), Transform = Transform(-5.0,0.0), Physic = Physic(1.0))

subscribe!(world, physic_sys, @query(world, Transform & Physic))
listen_to(physic_sys, render_sys)

run_system!(physic_sys)
run_system!(render_sys)

N = 3

for i in 1:N
    println("FRAME $i")

    # We dispatch data and each system will execute his `run!` function
    dispatch_data(world)
    blocker(world) # Will make the process wait for all systems to finish
end
```

> **Note** : the function `listen_to` just add the system as a listener, the 2 systems don't need each other. the listener (the last argument of the function) simply wait passively for data which can come from anyone, and the source just pass the results of his `run!` function to every system listening to him.

---

### Technical Overview

#### **Internal Storage**

Each components are stored in his own partitioned **fragment vector** layout. A fragmet vector is a data structure made during the process of maki g ReactiveECS.jl. It's like sparse set but represent a contiguous range of data as a fragment (chunk of a vector) and use an internal map (vector of UInt64) to know which fragment and with which offset each index have. 
When a new component is added, the internal map of his fragment vector resizes to match the size of others, ensuring consistent index mapping. This is usually done at component creation with `register_component!(world, type)`. 
When an entity is added, It's added to a partition representing its archetype, and the index in that partition becomes the entity ID. Upon removal, the entity is swapped with the last entity of the partition and the partition shrink.

Unused slots remain undefined but reserved — enabling **fast pooling** and simple memory reuse.

This layout allows fast iterations du to partitioning but also decently fast structural changes do to the sparse nature of fragment vectors.

```
        INTERNAL STORAGE
 _______________________________________________________
|   |     Health    |     Transform    |    Physic     |
|-------------------------------------------------------
|   |      hp       |    x    |    y   |   velocity    |
|-------------------------------------------------------
| 1 |     100       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 2 |     150       |   1.0   |  1.0   |      //       |
|-------------------------------------------------------
| 3 |     ___       |   ___   |  ___   |      //       |
|-------------------------------------------------------
| 4 |     ___       |   ___   |  ___   |      //       |
|-------------------------------------------------------
| 5 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
| 6 |     50        |  -5.0   |  1.0   |     1.0       |
|-------------------------------------------------------
```

* Rows 1–4: partition for entities with `Health` and `Transform`

  * Rows 1–2 are **active**, 3–4 are **pooled**
* Rows 5–6: partition for entities with `Health`, `Transform`, and `Physic`

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

The `ECSManager` acts as the central coordinator. It holds all components using a **Struct of Arrays (SoA)** layout for cache-friendly access patterns. When `dispatch_data` is called, the manager sends each subscribed system a **`Query`**.

A  `Query` is a struct containing the matching partitions for that system. Each partition contain the range of the matching entities and these range can easily be accessed with `@foreachrange`

This design eliminates the need for explicitly optional components, systems technically have access to all registered components due to the sparse nature of the data's storage, but only the relevant subset is prefiltered and passed to them for iteration.

### Subscription Logic

When a system subscribes to a query, the manager object just add it to the list of system with his query (like a new element in a dictionnary).

The `subscribe!` function has a time complexity of **`O(1)`**, since it's just as simple as adding an element to a dict.
Note that this means the manager doesn't keep track of system types but of systems instances. So multiple instance of the same system can coexist with different queries.

### System Execution

Calling `run_system!` starts the system in a blocking task, which suspends execution until the `ECSManager` dispatches the required data. Once unblocked, the system's `run!` function is invoked with its input data. Upon completion, the result is automatically forwarded to all systems registered as listeners via `listen_to`.

To prevent runtime issues, **cyclic dependencies between systems are detected recursively** during `listen_to` registration, and a warning is emitted if a cycle is found.

Then, the system listening to another one will be executed as asynchronous task so there is no enforced execution order. Instead, systems can be chained via listener relationships.

If a system encounters an error during execution, it will raise a warning that can be logged and the system's execution will be stopped. A crashed system can be restarted by simply calling `run_system!` again.

### Race Condition

To prevent race conditions during systems's executions, we provide `HierarchicalLock` which is a tree of lock where each field (and nested sub fields) of a component possess a lock.
For example if we have system A, system B, system C running in parallel and a component Transform. System A want to write on the x field of transform, B on the y field and C want to read both and eventually write. Instead of putting a lock on transform (which may also block system B), system A will just lock the x field which he his using while System B will lock the y field.
This allow granular control over parallelism while introducing a low overhead (400ns for the lifecycle of a lock.).

### Event system

ReactiveECS provide a fully functional event system. It leverage the [Notifyers.jl](https://github.com/Gesee-y/Notifyers.jl) package.
You can define a new package with `@Notifyer(arg1::T1, arg2::T2, ..., argn::Tn)`, see [Notifyers's doc](https://github.com/Gesee-y/Notifyers.jl/blob/main/docs/index.md). You can reuse all the features available in that package here. Meaning supports for:
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
     ┌────┴─────┬
     │          │         
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

### Dispatch Overhead

| Number of Systems  | Performance           |
| ------------------ | --------------------- |
| 2                  |  ~580 ns (0 alloc)    |
| 5                  |  ~1.3 μs (0 alloc)    |
| 10                 |  ~2.7 μs (0 alloc)    |
| 20                 |  ~5.3 μs (0 alloc)    |
| 50                 |  ~13.5 μs (0 alloc) |
| 100                |  ~26.1 μs (0 alloc) |
| 200                |  ~50.3 μs (0 alloc) |

> **Complexity**: `O(k)`, where `k` is the number of system subscriptions.
> **Note**: This system synchronization introduce a constant overhead of 10-15 μs

### Entity operations

* **Adding entity** : 1.21 μs (8 allocations: 896 bytes)
* **Removing entity** : 861 ns (1 allocations: 90 bytes)

> **Analysis**:
>
> * Adding an entity requires just adding the entity components to the matching partitions, so it's `O(c)` where `c` is the number of components the entity have.
> * Removing is just swapping the entity with the last valid one and then decrementing the range. It's `O(c)` where `c` is the number of component of the entity to remove.

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

---

## Advantages of RECS

- **High Performance**: Cache efficency, vectorized updates, etc.
- **Improved memory locality**: components stored in contiguous SoA layout with partitions to ensure data alignment.
- **Stable performance**: one dispatch per tick, no redundant queries.
- **Reactive Design**: `listen_to` enables decoupled, dynamic system pipelines.
- **Flexible Events**: Merge, one-shot, and prioritized events enhance reactivity.
- **Scalability**: Efficient for 100k+ entities, with pooling and SoA.
- **Extensibility**: Add systems at runtime with minimal code changes.
- **Profiling**: Built-in tools for debugging and optimization.
- **Ready for distributed architecture**: ECSManager can be centralized for multiplayer or server-client architectures.

## Actual limitation

- **Synchronization overhead**: There are some 10-50 μs due to synchronizing systems paid per frame
- **Asynchronous Complexity**: Reactive pipelines can be harder to debug, though mitigated by profiling tools.

---

## Conclusion

RECS overcomes classical ECS limitations by offering **better scalability**, **good stability**, **a reactive architecture**, and improved readiness for **parallel or distributed processing**.
This architecture is particularly suited for real-time simulation, 2D/3D games, and projects requiring dynamic reactivity without compromising performance.
This model has been implemented for my experimental game engine in Julia. It combines ECS simplicity with targeted dispatch reactivity, without sacrificing performance.

For technical questions or contributions, feel free to reach out.
