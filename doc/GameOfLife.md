## Conway's Game of life

The Conway's game of life is a popular game in which cells move, live and die
On [Rust discourse](https://users.rust-lang.org)'s thread "[Please don't put ECS in your game engine](https://users.rust-lang.org/t/please-dont-put-ecs-into-your-game-engine/49305)" started a game developper, frustrated with Unity's ECS where updating cell's state within the same frame was a nightmare. It was a big turn down for him that he decided to turn back to Lua's LOVE2D, which provide more flexibility.

#### Understanding the ECS Limitation

In traditional ECS frameworks, systems are often tightly coupled to the engine's update loop, which processes systems in a predefined order (e.g., at frame start or end). The Rust thread's Game of Life example highlights frustration with this rigidity:
- The user wanted a system to process cell entities (with components like position and state) immediately, updating their state (alive/dead) based on neighbor counts within the same update cycle.
- Many ECS frameworks require systems to register with the engine, adhere to its scheduling, and defer updates, leading to delayed state changes or complex workarounds.

## The RECS Model: Reactive, Composable, Asynchronous

[ReactiveECS.jl](https://github.com/Gesee-y/ReactiveECS.jl) is a Julia-based ECS framework designed from the ground up to support **data-driven, reactive, and asynchronous system execution**.

Here’s how RECS solves the core issues:

### Subscription-Based Filtering

Systems declare the components they care about using `subscribe!`, and RECS builds optimized queries (via archetypes) to pass only the relevant entities to the system.

This ensures minimal overhead and aligns with how Game of Life needs to query cells with `CellState` and `Position`.

```julia
subscribe!(ecs, life_sys, (CellStateComponent, TransformComponent))
```

---

### Reactive System Chaining

RECS introduces a `listen_to` mechanism that enables **dataflow-based composition**:

* Systems can “listen” to another system’s output.
* Data returned by one system can be directly forwarded to the next, in order.
* Multiple systems can listen to the same source, forming a directed acyclic graph (DAG).

This allows the `RenderSystem` to respond to `LifeSystem`'s output immediately, within the same execution pass.

```julia
listen_to(life_sys, render_sys)
```

Need to inject a system in the middle of a flow? Use:

```julia
get_into_flow(source_system, intermediate_system)
```

---

### Asynchronous Execution

Systems are launched using `run_system!`, which creates an **asynchronous coroutine**. These systems suspend until data is available, then resume to process and return results.

This model avoids rigid frame-based scheduling. For example:

```julia
run_system!(life_sys)
run_system!(render_sys)
dispatch_data(ecs)  # Triggers all data-dependent systems
```

Systems run only when their input data is dispatched—just like an event loop.

## RECS: Injecting Immediate Reactive Systems in Existing ECS Workflows

In many ECS frameworks, integrating a new system into an existing game loop is a non-trivial process. You often need to register the system, manually define its execution order, and handle data passing through custom middleware or deferred updates. This is especially problematic in cases like **Conway’s Game of Life**, where state transitions need to happen **immediately**, in the same tick, and affect rendering in real-time.

This article demonstrates how the **RECS ECS framework for Julia** solves these issues via:

* **Reactive system chaining** with `listen_to`
* **Runtime system injection** with `get_into_flow`
* **Multiple dispatch** to define distinct processing paths for a single system

We will show how you can plug a new system like `LifeSystem` into an already running ECS composed of `PhysicSystem` and `RenderSystem`, **without disrupting the existing code**.

---

## Part 1: An Existing ECS Workflow

Here’s a standard RECS setup with two systems: one for physics and one for rendering.

```julia
using ReactiveECS

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
```

### Physics System Logic

```julia
function ReactiveECS.run!(world, sys::PhysicSystem, data)
    E = world[sys]
    indices::Vector{Int} = data.value
    L = length(indices)

    transforms = E.Transform
    physics = E.Physic

    x_pos::Vector{Float32} = transforms.x
    velo::Vector{Float32} = physics.velocity
    dt::Float32 = sys.delta

    @inbounds for i in indices
        x_pos[i] += velo[i]*dt
    end
end
```

### Render System (First Variant)

```julia
function ReactiveECS.run!(_, ::RenderSystem, pos)
    for i in eachindex(pos)
        println("Entity at ($(pos[i].x), $(pos[i].y))")
    end
end
```

### System Setup

```julia
ecs = ECSManager()

physic_sys = PhysicSystem(1/60)
render_sys = RenderSystem()

subscribe!(ecs, physic_sys, (TransformComponent, PhysicComponent))
listen_to(physic_sys, render_sys)

run_system!(physic_sys)
run_system!(render_sys)
```

At this point, the ECS loop is already working. Now let’s see how to **inject a new system (Game of Life)** in this flow.

---

## Part 2: Injecting `LifeSystem` Dynamically

We want to extend the current ECS without touching the existing systems. We'll plug `LifeSystem` **between** `PhysicSystem` and `RenderSystem`, while also using **multiple dispatch** to specialize how `RenderSystem` processes the new output.

---

### Life System Definition

```julia
@component CellState begin
    alive::Bool
end

# This structure just serve as a wrapper for the CellState. This way we can use multiple dispatch.
# WeakRef are easier to pass through systems
# No worry about GC. Since we return a component, it's always referenced in the ECSManager
struct CellData
    data::WeakRef
end

@system LifeSystem begin
    size::NTuple{2, Int}
end

function ReactiveECS.run!(world, sys::LifeSystem, data)
    E = world[sys]
    indices = data.value
    state = E.CellState
    pos = E.Position

    new_states = copy(state.alive)

    for i in eachindex(indices)
        x, y = pos.x[i], pos.y[i]
        neighbors = count_neighbors(x, y, E, indices)
        new_states[i] = state.alive[i] ? (neighbors in (2,3)) : (neighbors == 3)
    end

    state.alive .= new_states
    return CellData(WeakRef(state))
end

function count_neighbors(x, y, E, indices)
    pos_data = E.Position
    state_data = E.CellState
    count = 0

    for i in eachindex(indices)
        nx, ny = pos_data.x[i], pos_data.y[i]
        if abs(nx - x) ≤ 1 && abs(ny - y) ≤ 1 && !(nx == x && ny == y)
            count += state_data.alive[i] ? 1 : 0
        end
    end
    return count
end
```

---

### Render System (Second Variant with Multiple Dispatch)

Here’s where **Julia's multiple dispatch** shines:

```julia
function ReactiveECS.run!(_, ::RenderSystem, ref::CellData)
    cell_data = ref.data.value
    for (i, cell) in enumerate(cell_data.data)
        println("Cell $i is $(cell.alive ? "alive" : "dead")")
    end
end
```

The same `RenderSystem` now handles both `Transform` output and `CellData`, **without if-else logic or type checks**.

---

### Plugging `LifeSystem` into the Flow

```julia
life_sys = LifeSystem((10,10))
subscribe!(ecs, life_sys, (CellStateComponent, TransformComponent))

# We make the render system wait for data coming from the LifeSystem
listen_to(life_sys, render_sys)

run_system!(life_sys)
```

No modification to `PhysicSystem` or `RenderSystem` was required. The only change is in how the data flows.

---

### Example Setup

```julia
size_x = life_sys.size[1]
size_y = life_sys.size[2]

for x in 1:size_x, y in 1:size_y
    create_entity!(ecs; 
        Physic = PhysicComponent(0.0f0),
        CellState = CellStateComponent(rand(Bool)), 
        Transform = TransformComponent(x, y)
    )
end
```

---

### Game Loop

```julia
for frame in 1:5
    println("FRAME $frame")
    dispatch_data(ecs)
    yield()
    sleep(0.016)
end
```

#### Performance Considerations

The RECS documentation provides benchmarks indicating efficient processing:
- **Dispatch Performance**: ~980 ns for updating 16K entities with 3 systems, which is a low enough overhead for these process.
- **Entity Operations**: Adding an entity takes ~869 ns (\(O(n + k)\)), and removing takes ~168 ns (\(O(k)\)), supporting fast system integration.

For Game of Life, where thousands of cells might be processed, RECS's cache-friendly SoA layout and precomputed archetype indices ensure efficient data access, addressing performance concerns raised in the Rust thread about ECS overhead.

## Conclusion

Most ECS frameworks treat system orchestration as a static, engine-level concern. RECS flips that by allowing systems to be composed **like reactive functions**, enabling **local reasoning, modular testing, and immediate system feedback**—all features missing from traditional ECS architectures.

By leveraging Julia’s strengths (coroutines, multiple dispatch, macros), RECS enables seamless, dynamic workflows for high-performance real-time simulations.

This design makes RECS especially well-suited for educational simulations, cellular automata, or complex pipelines where you need fine-grained control over execution order—without sacrificing ECS principles like decoupling and data locality.

---
