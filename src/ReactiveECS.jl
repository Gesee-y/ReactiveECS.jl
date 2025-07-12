module ReactiveECS

using Reexport
using StructArrays

include(joinpath("NodeTree.jl", "src", "NodeTree.jl"))
include(joinpath("Notifyers.jl", "src", "Notifyers.jl"))
include("hierarchical_lock.jl")

@reexport using .NodeTree
@reexport using .Notifyers
using .Threads
@reexport using .HierarchicalLocks

export AbstractComponent, AbstractSystem

include(joinpath("LogTrace.jl", "src", "LogTrace.jl"))

"""
    abstract type AbstractComponent

Supertype of all components.
"""
abstract type AbstractComponent end

"""
    abstract type AbstractSystem

Supertype of all system
"""
abstract type AbstractSystem end

const Optional{T} = Union{Nothing, T}

# Mutable Ints
include("mutable_int.jl")
# Entities management
include("entity.jl")
# Table representation
include("table.jl")
# Components management
include("component.jl")
# Manager object
include("manager.jl")
# Systems management
include("system.jl")
# Operations
include("operations.jl")
# Utilitary
include("utils.jl")

end # module ReactiveECS
