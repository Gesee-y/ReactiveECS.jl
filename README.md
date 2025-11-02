# ReactiveECS.jl v2: Reconciling Performance and Flexibility 

A high-performance, modular, event-driven and fragment-vector based ECS (Entity-Component-System) architecture written in Julia. Designed for game engines, simulations, or any data-oriented architecture needing maximum performances with extreme flexibility.

It's already used by the highly flexible 2D/3D game engine [Cruise.jl](https://github.com/Gesee-y/Cruise.jl) one of his core architecture 

---

## Installation

```julia
julia> ]add ReactiveECS
```

For development version

```julia
julia> ] add https://github.com/Gesee-y/ReactiveECS.jl
```

---

## Characteristics and Features  

- **Fast**: One of the fastest ECS in Julia, already outperforming some well-established C/C++ ECS. See [this](https://github.com/Gesee-y/ReactiveECS.jl/blob/main/doc/Achitecture.md).
- **Maximum memory locality**: Using partitions which are range of data, it makes sure entities are tighly packed in memory, allowing vectorization.
- **Efficient structural changes**: With fragment vectors which allow fast entities/components add/remove.
- **Performant random access iteration**: With optimized blocks iterators from fragment vectors.
- **Flexible**: Add, remove, or chain systems at runtime, you can even inject a system in the middle of a chain.
- **Changes tracking**: Optionally watch changes on a field of component.
- **Granular concurrency safety**: Provides specialized tools like **HierarchicalLock** to help you cleanly manage concurrency.  
- **Inherently ready for parallelism**: Its partitioned table already acts as chunks for parallel processing with cycles detection.
- **Easy to use**: Thanks to Julia’s powerful macros, which abstract away complexity.
- **Allow lazy operations**: Such as lazy entities creation.
- **Entities hierarchy**: You are allowed to build parent-child relationships betwenn entities.
- **Multiple components per entities**: Through multiple tables and foreign keys.
- **No memory movements once stable**: Once the ECS reached its peak, no more allocations or desallocations.

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
end

function ReactiveECS.run!(world, sys::MoveSystem, query::Query)
    positions = get_component(world, :Position)  # Get all Position components
    dt = sys.dt

    @foreachrange query begin
        pblock = get_block(positions, range)
        r = offset(range, get_offset(positions, range)
        for i in r
            pos = pblock[i]
            pblock[i] = Position(pos.x+dt, pos.y)  # Move entity along x-axis
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

## License

MIT License © 2025 \[Kaptue Talom Lael]

---

## Contributing

PRs and issues are welcome. Feel free to open discussions if you plan to adapt this ECS for your own game engine or simulation framework.

---

## Contact

For technical questions, ideas, or contributions:

Email: [gesee37@gmail.com](mailto:gesee37@gmail.com)
