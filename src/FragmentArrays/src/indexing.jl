################################################################################################################################################
################################################################# INDEXING #####################################################################
################################################################################################################################################

export get_iterator, get_iterator_range, prealloc_range, hasindex

const OFFSET_MASK = ((1 << 32)-1)
const BLOCK_MASK = ((1 << 32)-1) << 32

function Base.getindex(f::FragmentVector{T,C,BinarySearchIndexing}, i)::T where {T, C<:AbstractFragmentLayout}
	idx = _new_block_idx(f.offset, i)
    @boundscheck 0 < idx || throw(BoundsError(f, i))

    blk, off = f.data[idx], f.offset[idx]
	
	@boundscheck _outside_block(blk, off, i) && error("The index [$i] doesn't exist or have been deleted")

	return @inbounds blk[i-off]
end

function Base.setindex!(f::FragmentVector{T,C,BinarySearchIndexing}, v, i) where {T, C<:AbstractFragmentLayout}
    idx = _new_block_idx(f.offset, i)
    0 < idx || return insert!(f, i, v)

    blk, off = f.data[idx], f.offset[idx]
    
    _outside_block(blk, off, i) && return insert!(f, i, v)

    return @inbounds blk[i-off] = v
end

Base.size(f::FragmentVector) = (length(f),)
Base.size(f::FragmentVector, i) = size(f)[i]

Base.eachindex(f::FragIter) = eachindex(f.block)
Base.eachindex(f::FragIterRange) = eachindex(f.block)
Base.getindex(f::FragIter, i) = (f.block[i], f.ids[i])
Base.getindex(f::FragIter{T}, i) where T <: Tuple = (f.block[i]..., f.ids[i])
Base.getindex(f::FragIterRange, i) = (f.block[i], f.range[i])
hasindex(f::FragmentVector, i) = begin
    id = _new_block_idx(f.offset, i)
    return _inside_block(f.data[id], f.offset[id], i)
end
function Base.iterate(f::FragIterRange, state=1)
    state > length(f.block) && return nothing
    return ((f.block[state], f.range[state]), state+1)
end
function Base.iterate(f::FragIter, state=1)
    state > length(f.block) && return nothing
    return ((f.block[state], f.ids[state]), state+1)
end
function Base.iterate(f::FragIter{T}, state=1) where T <: Tuple
    state > length(f.block) && return nothing
    return ((f.block[state]..., f.ids[state]), state+1)
end

function Base.iterate(f::FragmentVector{T}) where T
    return _iterate_fragment(f, 1, 1)
end

function Base.iterate(f::FragmentVector{T}, state) where T
    block, loc = state
    return _iterate_fragment(f, block, loc)
end

function _iterate_fragment(f::FragmentVector{T}, block::Int, loc::Int) where T
    while block <= length(f.data)
        blk = f.data[block]
        if loc <= length(blk)
            return (blk[loc], (block, loc + 1))
        else
            block += 1
            loc = 1
        end
    end
    return nothing
end


function get_iterator_range(f::FragmentVector{T,L}, vec; shouldsort=false) where {T,L}
    begin
        if shouldsort
            sort!(vec)
        end

        result = FragIterRange{L}()
        l2 = length(vec)
        i = 1
        rstart  = vec[begin]
        rend = vec[end]

        while i <= rend
            id = _new_block_idx(f.offset, rstart)
            if iszero(id)
                rstart += 1
                continue
            end
            blk, off = f.data[id], f.offset[id]
            st, ed = max(off, rstart), min(rend, off+length(blk))
            _outside_block(blk, off, st) && break

            i += length(st:ed)+1
            rstart = ed+1

            push!(result.block, blk)
            push!(result.range, st-off:ed-off)
        end

        return result
    end
end

function get_iterator(f::FragmentVector{T, C}, vec; shouldsort=false) where {T, C}
    shouldsort && sort!(vec)
    l = length(f)
    l2 = length(vec)

    n = 0
    i = 1
    result = FragIter{C}()

    @inbounds while i <= l2
        s = vec[i]
        si = i
        block = get_block(f, s)
        off = get_offset(f, s)

        while i <= l2 && vec[i] - off <= length(block)
            i += 1
        end

        push!(result.block, block)
        push!(result.ids, vec[si:i-1] .- off)
    end

    return result
end

function get_iterator(fs::T, vec; shouldsort=false) where T <: Tuple
    shouldsort && sort!(vec)
    l2 = length(vec)

    n = 0
    i = 1
    result = FragIter{_to_vec_type(fs)}()

    @inbounds while i <= l2
        s = vec[i]
        si = i
        fix = Base.Fix2(get_block, s)
        blocks = fix.(fs)
        l = length(blocks[begin])
        off = get_offset(fs[begin], s)

        while i <= l2 && vec[i] - off <= l
            i += 1
        end

        push!(result.block, blocks)
        push!(result.ids, vec[si:i-1] .- off)
    end

    return result
end

function _new_block_idx(arr, x) 
    isempty(arr) && return 0
    x < arr[begin] && return 0
    ##x >= arr[end] && return length(arr)
    lo = 1
    hi = length(arr)
    idx = 0
    @inbounds while lo <= hi
        mid = (lo + hi) >>> 1
        v = arr[mid]
        m = v < x
        idx += (mid - idx) * m
        lo  += (mid + 1 - lo) * m
        hi  -= (hi - (mid - 1)) * (1 - m)
    end
    return idx
end



function _to_vec_type(::T) where T

    return Tuple{_to_vec.(T.parameters)...}
end

_to_vec(::Type{<:FragmentVector{T, C}}) where {T, C} = C