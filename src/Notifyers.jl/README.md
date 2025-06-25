# Notifyers.jl  

## Introduction  

Event-driven systems are essential in many domains: GUI applications, robotics, plotting, etc. Existing packages like [Reactive.jl](https://github.com/JuliaGizmos/Reactive.jl) (asynchronous signals) and [Observables.jl](https://github.com/JuliaGizmos/Observables.jl) (synchronous observables) address this need.  

**Notifyers.jl** combines the best of both worlds by introducing `Notifyer` objects that rely on **states** to define their behavior. These states (synchronous, asynchronous, etc.) can be mixed to create unique event-handling workflows.  

## Installation  

For the stable release:  
```julia  
julia> ]add Notifyers  
```  

For the development version:  
```julia  
julia> ]add https://github.com/Gesee-y/Notifyers.jl.git  
```  

## Features  

- **Intuitive syntax** inspired by [Godot Engine signals](https://docs.godotengine.org/en/stable/classes/class_signal.html):  
  ```julia  
  @Notifyer name(arg1::Type1, ..., argn::Typen)  
  ```  
- **State-driven behavior**: Define states for delayed calls, async tasks, and more.  
- **State sharing**: Pass states between `Notifyer` objects. 
- **Parent-child relationship** : A Notifyer can have childrens and propagate his updates to them.

## Why Notifyers.jl?  

While matching the performance of similar packages, `Notifyers.jl` provides a **versatile solution** for projects requiring both synchronous and asynchronous [observer patterns](https://www.geeksforgeeks.org/observer-pattern-set-1-introduction/).  

## Why States?  

After using Reactive.jl and Observables.jl, I sought a way to unify their strengths. Inspired by [OpenGL’s state machine](https://www.khronos.org/opengl/wiki/OpenGL_Context), `Notifyers.jl` adopts a simple workflow:  

1. **Set a state**.  
2. **Perform operations** within that state.  
3. **Exit the state**.  

## Documentation  

Explore the full documentation [here](https://github.com/Gesee-y/Notifyers.jl/blob/main/docs/index.md).  

## License  

MIT License. See [LICENSE](https://github.com/Gesee-y/Notifyers.jl/blob/main/License.txt).  

## Contributing  

Contributions are welcome!  

1. [Fork the repository](https://github.com/Gesee-y/Notifyers.jl/fork).  
2. Create a new branch.  
3. Submit a Pull Request.  

## Bug Reports  

Found an issue? Report it [here](https://github.com/Gesee-y/Notifyers.jl/issues).  
