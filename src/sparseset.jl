############################################################################################################################################
############################################################### SPARSESET IMPLEMENTATION ###################################################
############################################################################################################################################

using SparseArrays

struct SparseSet{T,V}
    sparse::Vector{T}
    dense::Vector{Int}
    values::Vector{V}

    function SparseSet{T,V}(max_id) where {T,V}
        new{T,V}(zeros(T, max_id), Int[], V[])
    end
end

struct StaticHashMap{K,V}
    keys::Vector{K}
    vals::Vector{V}
    used::BitVector

    ## Constructors

    function StaticHashMap{K,V}(capacity) where {K,V}
	    keys = fill(zero(K), capacity)
	    vals = Vector{V}(undef, capacity)
	    used = falses(capacity)
	    return new{K,V}(keys, vals, used)
    end
end


############################################################ OPERATIONS ###################################################################

function Base.getindex(s::SparseSet, id)
    idx = s.sparse[id]
    idx == 0 && error("No value for id $id")
    return s.values[idx]
end

function Base.setindex!(s::SparseSet{T,V}, value::V, id) where {T,V}
    idx = s.sparse[id]
    if idx == 0
        push!(s.dense, id)
        push!(s.values, value)
        s.sparse[id] = length(s.dense)
    else
        s.values[idx] = value
    end
end

function delete!(s::SparseSet, id)
    idx = s.sparse[id]
    idx == 0 && return
    last = length(s.dense)
    last_id = s.dense[last]
    s.dense[idx] = last_id
    s.values[idx] = s.values[last]
    s.sparse[last_id] = idx
    pop!(s.dense)
    pop!(s.values)
    s.sparse[id] = 0
end

hasindex(s::SparseSet, id) = s.sparse[id] != 0

###################### HashMap

mutable struct ArchetypeMap{V}
    keys::Vector{UInt128}
    vals::Vector{V}
    used::BitVector
    mask::Int

    ## Constructors

    function ArchetypeMap{V}(capacity::Int=256) where V
        cap = nextpow(2, capacity)
        new{V}(fill(0x0, cap), Vector{V}(undef, cap), falses(cap), cap-1)
    end
end

@inline function Base.getindex(m::ArchetypeMap, key::UInt128)
    i = (key * 11400714819323198485) & m.mask + 1
    while m.used[i]
        m.keys[i] == key && return m.vals[i]
        i = (i & m.mask) + 1
    end
    error("key not found")
end

@inline function Base.setindex!(m::ArchetypeMap{V}, val::V, key::UInt128) where V
    i = (key * 11400714819323198485) & m.mask + 1
    while m.used[i]
        if m.keys[i] == key
            m.vals[i] = val
            return
        end
        i = (i & m.mask) + 1
    end
    m.used[i] = true
    m.keys[i] = key
    m.vals[i] = val
end

function Base.haskey(m::ArchetypeMap, key)
    i = (key * 11400714819323198485) & m.mask + 1
    while m.used[i]
        if m.keys[i] == key
            return true
        end
        i = (i & m.mask) + 1
    end

    return false
end