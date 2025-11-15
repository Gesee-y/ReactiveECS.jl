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

mutable struct ArchetypeMap{V}
    keys::Vector{UInt128}
    vals::Vector{V}
    used::BitVector
    mask::UInt128
    index::Vector{Int}

    ## Constructors

    function ArchetypeMap{V}(capacity::Int=256) where V
        cap = nextpow(2, capacity)
        new{V}(fill(0x0, cap), Vector{V}(undef, cap), falses(cap), cap-1, Int[])
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

const MUL_NUM = UInt128(11400714819323198485)

Base.getindex(m::ArchetypeMap, key) = getindex(m, UInt128(key))
@inline function Base.getindex(m::ArchetypeMap, key::UInt128)
    i = (key * MUL_NUM) & m.mask + 1
    while m.used[i]
        m.keys[i] == key && return m.vals[i]
        i = (i & m.mask) + 1
    end
    error("key $(key) not found")
end
Base.length(a::ArchetypeMap) = length(a.index)
Base.setindex!(m::ArchetypeMap, v, key) = setindex!(m, v, UInt128(key))
@inline function Base.setindex!(m::ArchetypeMap{V}, val::V, key::UInt128) where V
    i = (key * MUL_NUM) & m.mask + 1
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
    push!(m.index, i)
end

function Base.iterate(m::ArchetypeMap, state=1)
    state <= length(m.index) || return nothing
    i = m.index[state]
    return ((m.keys[i], m.vals[i]), state+1)
end

function Base.haskey(m::ArchetypeMap, key)
    i = (key * MUL_NUM) & m.mask + 1
    while m.used[i]
        if m.keys[i] == key
            return true
        end
        i = (i & m.mask) + 1
    end

    return false
end