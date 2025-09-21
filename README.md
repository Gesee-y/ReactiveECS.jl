# ReactiveECS.jl: Reconciling Performance and Flexibility 

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
- **Flexible**: Add, remove, or chain systems at runtime — you can even inject a system in the middle of a chain.  
- **Granular concurrency safety**: Provides specialized tools like **HierarchicalLock** to help you cleanly manage concurrency.  
- **Inherently ready for parallelism**: Its partitioned table already acts as chunks for parallel processing.  
- **Easy to use**: Thanks to Julia’s powerful macros, which abstract away complexity.  
- **Database-like queries**: Query entities across tables, use foreign keys, and more.  

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
  By using **partitions**. Continuous ranges within partitions represent entities that use the same set of components. Archetypes here are symbolic — entities still technically have all components, but partitions let us group those exclusively in use.  

- **Memory waste**  
  This layout does consume more memory than archetype-based ECS. To mitigate this, RECS introduces **multiple tables**.  
  Each table is specialized for a subset of components (e.g., an `ENEMY` table with enemy-specific components, a `BULLET` table, or a `PROPS` table). Queries then work by intersecting partitions across these tables, ensuring efficient memory use.

---

## Performances

It’s a critical aspect of any ECS, and RECS doesn’t neglect it.  
Its partitioned table offers performance comparable to an archetype-based ECS.  

Partitions (symbolic archetypes) pack similar entities continuously in memory without indirections, enabling top performance and reducing pointer chasing. This also minimizes the need for frequent table switches, which is a common overhead in archetype-based ECS.  

This topic is discussed in more detail [here](https://github.com/Gesee-y/ReactiveECS.jl/blob/main/doc/Achitecture.md).

___

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

## License

MIT License © 2025 \[Kaptue Talom Lael]

---

## Contributing

PRs and issues are welcome. Feel free to open discussions if you plan to adapt this ECS for your own game engine or simulation framework.

---

## Contact

For technical questions, ideas, or contributions:

Email: [gesee37@gmail.com](mailto:gesee37@gmail.com)
