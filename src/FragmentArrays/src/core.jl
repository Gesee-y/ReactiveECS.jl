######################################################################################################################
################################################## CORE ##############################################################
######################################################################################################################

export FragmentVector

export AbstractFragmentVector, AbstractFragmentLayout, AbstractArrayLayout
export VectorLayout, FragmentIndexingStyle

abstract type AbstractFragmentVector{T, L} <: AbstractVector{T} end
abstract type AbstractFragmentLayout end
abstract type AbstractArrayLayout{T} <: AbstractFragmentLayout end
abstract type FragmentIndexingStyle end

struct VectorLayout{T} <: AbstractArrayLayout{T}
    data::Vector{T}

    ## Constructors

    VectorLayout{T}(::UndefInitializer, n) where T = new{T}(Vector{T}(undef, n))
    VectorLayout(args::T...) where T = new{T}(T[args...])
    VectorLayout{T}(args...) where T = new{T}(T[args...])
end

struct BinarySearchIndexing <: FragmentIndexingStyle end

"""
    mutable struct FragmentVector{T}
    	data::Vector{Vector{T}}
	    map::Vector{Int}
	    offsets::Vector{Int}

Represent a fragmented array. Each time a deletion happens, the array fragment it's data in multiple vectors to
maintain contiguity and eep the globalindex valid
"""
mutable struct FragmentVector{T, L, I} <: AbstractFragmentVector{T, L}
	data::Vector{L}
	map::Vector{UInt}
	offset::Vector{Int}

	## Constructors

	FragmentVector{T, C, I}(::UndefInitializer, n) where {T, C, I} = new{T, C{T}, I}(C{T}[], fill(zero(UInt), n), Int[])
    FragmentVector{T, C}(::UndefInitializer, n) where {T, C} = FragmentVector{T, C, BinarySearchIndexing}(undef, n)
    FragmentVector{T}(::UndefInitializer, n) where T = FragmentVector{T, VectorLayout}(undef, n)

    FragmentVector{T, C, I}(args...) where {T, C, I} = new{T, C{T}, I}(C{T}[initialize_layout(C{T}, args...)], fill(one(UInt), length(args)), Int[])
	FragmentVector{T, C}(args...) where {T, C} = FragmentVector{T, C{T}, BinarySearchIndexing}(args...)
	FragmentVector(args::T...) where T = FragmentVector{T, VectorLayout}(args...)
end

struct FragIterRange{T}
    block::Vector{T}
    range::Vector{UnitRange{Int}}

    ## Constructors

    FragIterRange{T}() where T = new{T}(T[], UnitRange{Int}[])
end

struct FragIter{T}
	block::Vector{T}
	ids::Vector{Vector{Int}}

	## Constructors

	FragIter{T}() where T = new{T}(T[], Vector{Int}[])
end

function Base.show(io::IO, f::FragmentVector)
    print(io, "[")
    n = length(f)
    last = 1
    for i in eachindex(f.data)
        blk, off = f.data[i], f.offset[i]
        for i in last:off
            print(io, ".")
            print(io, ", ")
        end
        for elt in blk
            print(io, elt)
            print(io, ", ")
        end

        last = off+length(blk)
    end
    print(io, "]")
end
Base.show(f::FragmentVector) = show(stdout, f)

################################################################################ HELPERS ####################################################################################

_initialize(::Vector{T}, args...) where T = T[args...] 