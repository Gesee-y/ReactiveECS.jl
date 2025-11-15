module ReactiveECS

using Reexport
using StructArrays
using FieldViews
@reexport using ECSInterface

include(joinpath("NodeTree.jl", "src", "NodeTree.jl"))
include(joinpath("Notifyers.jl", "src", "Notifyers.jl"))
include(joinpath("FragmentArrays", "src", "FragmentArrays.jl"))
include("hierarchical_lock.jl")

@reexport using .NodeTree
@reexport using .Notifyers
@reexport using .FragmentArrays
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
include("mutable_ints.jl")
# Sparse sets
include("sparseset.jl")
# Entities management
include("entity.jl")
# SoA Layout
include("soa.jl")
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
