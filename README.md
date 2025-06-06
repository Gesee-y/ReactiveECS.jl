# Event-Driven ECS in Julia

A high-performance, modular, event-driven ECS (Entity-Component-System) architecture written in Julia. Designed for game engines, simulations, or any data-oriented architecture requiring reactive system dispatching and efficient memory layout.

> Not a Pub/Sub system. This ECS is "event-driven" in the sense that systems subscribe to *archetypes* and only receive entities that match their component needs.

---

## Features

- **Data-oriented ECS** with archetype-based grouping.
- **Reactive dispatch system**: systems only receive relevant entities each frame.
- **Chunk-based memory layout** for cache efficiency and performance.
- **Multithreading-ready**: systems can process chunks in parallel.
- **Dynamic system subscription** at runtime.
- **Server-ready architecture**: centralized dispatch can scale across networked clients.
- **Benchmark proven** with consistent performance across large entity counts.

---

## Installation

```julia
julia> ] add https://github.com/Gesee-y/EDECS.jl
````

> Replace the URL with the actual GitHub repo link when available.

---

## Architecture Overview

* `Entity`: an ID with a map of named components.
* `Component`: any struct implementing `AbstractComponent`.
* `System`: a process that subscribes to an archetype and operates on matching entities.
* `ECSManager`: the central controller that stores entities, handles subscriptions, and dispatches entity batches to systems.

For a detailled analysis check the [architecture](https://github.com/Gesee-y/EDECS.jl/doc/Architecture.md)
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
