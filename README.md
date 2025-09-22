# ReactiveECS.jl v2: Reconciling Performance and Flexibility 

A high-performance, modular, event-driven ECS (Entity-Component-System) architecture written in Julia. Designed for game engines, simulations, or any data-oriented architecture maximum performances with extreme flexibility.

---

## Installation

```julia
julia> ]add ReactiveECS
```

For development version

```julia
julia> ] add https://github.com/Gesee-y/ReactiveECS.jl
````

---

## Characteristics  

- **Fast**: The fastest ECS in Julia, already outperforming some well-established C/C++ ECS. See [this](https://github.com/Gesee-y/ReactiveECS.jl/blob/main/doc/Achitecture.md).
- **Maximum memory locality**: Partitions makes sure entities are tighly packed in memory, allowing vectorization.
- **Flexible**: Add, remove, or chain systems at runtime — you can even inject a system in the middle of a chain.
- **Changes tracking**: Optionally watch changes on a field of component.
- **Granular concurrency safety**: Provides specialized tools like **HierarchicalLock** to help you cleanly manage concurrency.  
- **Inherently ready for parallelism**: Its partitioned table already acts as chunks for parallel processing with cycles detection.
- **Easy to use**: Thanks to Julia’s powerful macros, which abstract away complexity.  
- **Database-like queries**: Query entities across tables, use foreign keys, and more.
- **Allow lazy operations**: Such as lazy entities creation.
- **Entities hierarchy**: You are allowed to build parent-child relationships betwenn entities.
- **Multiple components per entities**: Through multiple tables and foreign keys.

---

## Example

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

function ReactiveECS.run!(world, sys::MoveSystem, query::Query)
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

---

## Overview  

Like almost every ECS, ReactiveECS (RECS) is built around two core principles:  

- **System orchestration**  
- **Memory layout**  

But RECS introduces a twist in how it handles these aspects.  

### System Orchestration  

Most ECS orchestrate systems with a static DAG (the graph of interactions between systems). Once all systems are declared, a scheduler builds the DAG and determines execution order.  

RECS completely breaks away from this principle and instead uses **reactive pipelines** to implicitly build the DAG of system execution.  

A central manager dispatches queries: each system subscribes to a query or to another system’s output.  
At each tick, the manager sends query results to relevant systems. Once they finish, they pass their results into the stream of dependent systems.  

This allows for extreme flexibility, such as:  
- Complete decoupling of systems  
- Runtime recovery for bugged systems  
- Reconfiguring the DAG at runtime  

### Memory Layout  

Memory layout is critical in every ECS, as it directly impacts performance and memory consumption. It’s what separates a good ECS from a bad one.  

RECS uses a **database-like memory layout** instead of archetype tables.  

How does it work?  
- Components are registered as columns with an SoA layout.  
- Entities are just rows in the table.  

The table is **dense**, ensuring maximum performances when iterating on it.
This layout, however, has a side effect: every entity has every component, even unused ones.  

This raises two main concerns:  

- **How can we represent archetypes?**  
  By using **partitions**. Continuous ranges within partitions represent entities that use the same set of components. By default a partition is about 4096 entities, once filled a new one is allocated. Archetypes here are symbolic — entities still technically have all components, but partitions let us group those exclusively in use. This mimic [Flecs](https://github.com/SanderMertens/flecs)'s archetypes table, ensuring memory locality and cache friendliness.

- **Memory waste**  
  This layout does consume more memory than archetype-based ECS. To mitigate this, RECS introduces **multiple tables**.  
  Each table is specialized for a subset of components (e.g., an `ENEMY` table with enemy-specific components, a `BULLET` table, or a `PROPS` table). Queries then work by intersecting partitions across these tables, ensuring efficient memory use.

This layout offers several advantages:

- **Easy parallelism**: Partitions are compact chunks of entities, making them naturally suited for parallel processing.  
- **No optionals**: Systems always see all components. They can simply use masks to skip entities without the required components, avoiding costly branching.  
- **Reduced memory movement**: Adding an entity just means writing a row. Removing one is a swap-remove. Adding or removing a component only changes the partition, not the data layout.  
- **Less pointer chasing**: Compared to archetypal ECS designs, there are fewer tables, which reduces indirection and improves cache locality.

---

## Performances

It’s a critical aspect of any ECS, and RECS doesn’t neglect it.  
Its partitioned table offers performance comparable to an archetype-based ECS.  

Partitions (symbolic archetypes) pack similar entities continuously in memory without indirections, enabling top performance and reducing pointer chasing. This also minimizes the need for frequent table switches, which is a common overhead in archetype-based ECS.

This topic is discussed in more detail [here](https://github.com/Gesee-y/ReactiveECS.jl/blob/main/doc/Achitecture.md).

Benchmarks have already been conducted against [Overseer.jl](https://github.com/louisponet/Overseer.jl) in two scenarios:

- **One system translating 100k entities with 1 component**:  
  - RECS: **163µs** with vectorization, **623µs** without  
  - Overseer: **2.7ms**  

- **Three systems performing differential calculations on 100k entities for various movements**:  
  - RECS: **10ms** without vectorization  
  - Overseer: **12ms**  

You can read the full [article here](https://discourse.julialang.org/t/reactiveecs-jl-v2-0-0-breaking-changes-for-massive-performance-boosts/130564/4).

## Systems variant

One of the powerful benefits of RECS lies in two key aspects:  

- **The manager executes system instances**:  
  When a system subscribes to a query or another system, it’s the actual instance — not just the type — that does so. You can create as many instances as you want and connect them as you like. Cycles are automatically detected.  

- **Systems can have multiple executions**:  
  Thanks to multiple dispatch, you can specialize different execution paths for your systems.

### Example

```julia
@system PhysicSystem begin
    dt::Float32
end

physic1 = PhysicSystem(1/60)
physic2 = PhysicSystem(1/30)

function ReactiveECS.run!(world, sys::PhysicSystem, query::Query)
    # declaring variables
    # Processing the query
    return data::MyCustomData 
end

# Here the system received data from another system
function ReactiveECS.run!(world, sys::PhysicSystem,  data::MyCustomData) 
    # My specialized process for this case
end

subscribe(world, physic1, @query(world, Position & Physic & ~Invincible) # We suppose these components exist
listen_to(physic1, physic2)
```

## Multiple Components 

At first glance, it seems impossible to add the same component multiple times to an entity, since this would require adding more rows to the table, leading to increased memory usage.  

To solve this, we borrow the **cardinality** concept from relational databases. To add multiple instances of a component to an entity, we create a separate table containing just that component as a column along with the ID of the entity it belongs to.  

By iterating over this table, we can apply the effects of these multiple identical components to their respective owners.

## Race Condition

To prevent race conditions during systems's executions, RECS provides `HierarchicalLock`s which is a tree of lock where each field (and nested sub fields) of a component possess a lock.
For example if we have system A, system B, system C running in parallel and a component Transform. System A want to write on the x field of transform, B on the y field and C want to read both and eventually write. Instead of putting a lock on transform (which may also block system B), system A will just lock the x field which he his using while System B will lock the y field.
This allow granular control over parallelism while introducing a low overhead (400ns for the lifecycle of a lock.).


## Event system

ReactiveECS provide a fully functional event system. It leverage the [EventNotifiers.jl](https://github.com/Gesee-y/EventNotifiers.jl) package.
You can define a new package with `@Notifyer(arg1::T1, arg2::T2, ..., argn::Tn)`, see [Notifyers's doc](https://github.com/Gesee-y/EventNotifiers.jl/blob/main/docs/index.md). You can reuse all the features available in that package here. Meaning supports for:
- **Merge**: Combine multiple events (e.g., 10 HP changes into 1).
- **Filtering**: Calls listener just if the event meet some conditions.
- **One-shot Listeners**: Execute once and unsubscribe.
- **Priorities and Delays**: Control execution order and timing.
- **Retention**: Store recent event values.
- **Performance**: 200 ns (no listeners), 1.6 µs (per listener), 4 µs (in single task state, independent from the listeners's count).

### Example 

```julia
@Notifyer on_damage(amount::Int)
enable_value(on_damage)
async_notif(on_damage)
critical_hit = filter(amount -> amount > 100, on_damage)

tick = EventNotifiers.fps(15) # Emit 15 times per second
connect(tick) do dt
    ## code 
end

```

## Tracking changes

You can use a `Notifyer` as field for a component and instantly track changes on his value.

```julia
@component Health begin
    hp::Notifyer
    max::Int
end

hp = Notifyer("", (Int,))
enable_value(hp) # The notifyer will keep hus last value
async_latest(hp, 1) # Only the latest callback will be emitted

health = Health(hp, 100)
```

## Tree Layout

The hierarchy between entities is ensured via the package [NodeTree](https://github.com/Gesee-y/NodeTree.jl), adding support for BFS/DFS and other traversal utility using `RECS.BFS_search(ecs)` or `RECS.DFS_search(ecs)`
We can visualize that hierarchy with `print_tree(io, ecs)`

### Example layout

```
ECSManager with 4 Nodes : 
    ├─Entity : "Entity 1"
    ├─Entity : "Entity 2"
    │   └─Entity : "Entity 3"
    └─Entity : "Entity 4"
```

## Debugging and profiling

We can switch to debug mode by overloading the function `debug_mode()`.
On this mode, the manager object will log the data received by each system, the data returned and profiling will be active
We can get the statistics of a system with `get_profile_stats(system)`. The format of the stats is the same as the one returned by `@timed`.
By default, the logs aren't directly written to a file. You should use `write!(io, ecs.logger)` where `ecs` is your `ECSManager` object.

The logger uses the module **LogTracer.jl**, inspired by Git.  
When you write a log, it is first staged in RAM so that performance isn’t impacted. Then you can call `flush(io, ecs.logger)` to actually write the logs to a file.  

Each time you write a log, a `Notifyer` named `ON_LOG` is triggered. This allows, for example, filtering only critical logs and flushing them when they are triggered.

## Limitations

While RECS offers high performance and extreme flexibility, there are a few limitations to be aware of:

- **Memory usage**: The database-like layout can consume more memory than archetype-based ECS designs, especially for large numbers of entities with many components.  

- **Learning curve**: Concepts like reactive pipelines, partitions, and multi-stream data flow require some time to master, particularly for newcomers to ECS.  

- **Dispatch and synchronization overhead**: While generally minimal, the reactive pipeline introduces some overhead due to system dispatch and managing concurrency.  

- **Manual optimizations**: RECS allows fine-grained control over loops and systems, which can boost performance. However, this also means beginners may need to invest extra effort to fully optimize their systems.  

- **Debugging complexity**: Because of the reactive data flows and multi-stream architecture, tracing and debugging issues can require more effort than in traditional ECS designs.

---

## License

MIT License © 2025 \[Kaptue Talom Lael]

---

## Contributing

PRs and issues are welcome. Feel free to open discussions if you plan to adapt this ECS for your own game engine or simulation framework.

---

## Contact

For technical questions, ideas, or contributions:

Email: [gesee37@gmail.com](mailto:gesee37@gmail.com)
