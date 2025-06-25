module RECS

include("..\\..\\NodeTree.jl\\src\\NodeTree.jl")
include(joinpath("..","..","Notifyers.jl","src","Notifyers.jl"))

using StructArrays
using OrderedCollections
using .Threads
using .NodeTree
using .Notifyers

const BitType = UInt128

"""
    Optional{T}

A short hand for `Union{T, Nothing}`.
"""
const Optional{T} = Union{T, Nothing}

"""
    abstract type AbstractComponent

Base type from which every component should derives.
"""
abstract type AbstractComponent end

"""
    abstract type AbstractSystem

Base type for any system.
"""
abstract type AbstractSystem end

include(joinpath("LogTrace.jl", "src", "LogTrace.jl"))
include("utils.jl")
include("entity.jl")
include("components.jl")
include("manager.jl")
include("systems.jl")
include("operations.jl")

init(::Type{BitVector}) = BitVector()
init(::Type{T}) where T <: Unsigned = T(0)
end # module