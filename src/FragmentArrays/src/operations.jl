#####################################################################################################################
###################################################### OPERATIONS ###################################################
#####################################################################################################################

export prealloc_range!, get_block, get_offset, numelt, get_block_and_offset

Base.length(f::FragmentVector) = isempty(f.data) ? 0 : f.offset[end]+length(f.data[end])
function Base.push!(f::FragmentVector, v)
    id = length(f.data)
	push!(f.data[id], v)
	f.capacity += 1
end

function Base.append!(f::FragmentVector, v)
	id = length(f.data)
	append!(f.data[id], v)
	f.capacity += length(v)
end

@inline function decode_mask(mask::UInt64)
    blockid = Int(mask >> 32)
    start   = Int(mask & OFFSET_MASK)
    return blockid, start
end

@inline function make_mask(blockid, start)
    return (UInt64(blockid) << 32) | UInt64(start & Int(OFFSET_MASK))
end

function _bump_block_starts!(map::Vector{UInt64}, from_index::Int)
    @inbounds offs[idx+1:end] .+= 1
   
end

function Base.insert!(f::FragmentVector{T,L}, i::Int, v::T) where {T,L}
	idx = _new_block_idx(f.offset, i)

	if iszero(idx)
		pushfirst!(f.data, L(v))
		pushfirst!(f.offset, i-1)

		return
	end

	blk, offs = f.data[idx], f.offset[idx]
    map = f.map
    lmap = length(map)
    ldata = length(f.data)

    if _inside_block(blk, offs, i)
        
        @inbounds begin
            lcl = i-offs
            insert!(blk, lcl, v) 
            @inbounds f.offset[idx+1:end] .+= 1
        end
        return
    end

    left_exists = (idx >= 1 && _inside_block(f.data[idx], f.offset[idx], i-1))
    right_exists = (idx+1 <= ldata && _inside_block(f.data[idx+1], f.offset[idx+1], i+1))
    
    if left_exists && right_exists
        
        lbid, lstart = idx, f.offset[idx]
        rbid, rstart = idx+1, f.offset[idx+1]
        
        left_block = f.data[lbid]
        right_block = f.data[rbid]

        push!(left_block, v)

        _fuse_block!(left_block, right_block)
        _deleteat!(f.data, rbid)
        _deleteat!(f.offset, rbid)
    elseif left_exists
    	lbid = idx
        push!(f.data[lbid], v)
    elseif right_exists
        rbid, rstart = idx+1, f.offset[idx+1]
        right_block = f.data[rbid]
        pushfirst!(right_block, v)
        @inbounds f.offset[idx+1] -= 1

    else
        nbid = length(f.data) + 1
        insert!(f.data, idx+1, L(v))
        insert!(f.offset, idx+1, i-1)
        return
    end
end

function Base.pop!(f::FragmentVector)
	f.map[end] = 0
	r = pop!(f.data[end])

	if isempty(f.data[end])
		pop!(f.data)
		pop!(f.offset)
	end

	return r
end

function Base.deleteat!(f::FragmentVector{T,L}, i) where {T, L}
	id = _new_block_idx(f.offset, i)
	if iszero(id) || !_inside_block(f.data[id], f.offset[id], i)
		return 
	end


	offset = f.offset[id]
    blk = f.data[id]

	idx = i - offset

	if idx == 1
		f.data[id] = L(blk[2:end]...)
		f.offset[id] += 1
    elseif idx == length(blk)
		pop!(blk)
	else
		vr = blk[idx+1:end]
		resize!(blk, idx-1)
		insert!(f.data, id+1, L(vr...))
		insert!(f.offset, id+1, i-1)
	end

	if isempty(f.data[id])
		_deleteat!(f.data, id)
		_deleteat!(f.offset, id)
	end
end

function Base.resize!(f::FragmentVector, n)
	l = length(f)

	n == l && return

	if n <= l
		while !isempty(f.offset) && f.offset[end] > n
			pop!(f.offset)
			pop!(f.data)
		end
	end

	f.capacity = n
end
Base.isempty(f::FragmentVector) = isempty(f.data)

function numelt(f::FragmentVector)
	l = 0
	for v in f.data
		l += length(v)
	end

	return l
end

function prealloc_range!(f::FragmentVector{T, C}, r::UnitRange{Int}) where {T, C}
    if isempty(f.data)
    	push!(f.data, C(undef, length(r)))
    	push!(f.offset, r[begin]-1)
    	return r
    end
    length(r) < 1 && return r
    lmap = length(f)
    ldata = length(f.data)

    rstart = max(first(r), 1)
    rend = last(r)
    sid, eid = _new_block_idx(f.offset, rstart), _new_block_idx(f.offset, rend)+1
    if eid - sid > 1
    	rend = f.offset[sid+1]
    	eid = sid+1
    end

    if sid > 0
    	lblk, loff = f.data[sid], f.offset[sid]
	    while rstart <= rend && _inside_block(lblk, loff, rstart)
	        rstart += 1
	    end
	end

	if eid <= length(f.data)
		rblk, roff = f.data[eid], f.offset[eid]
	    while rstart <= rend && _inside_block(rblk, roff, rend)
	        rend -= 1
	    end
	end

    if rstart > rend
        return rstart:rstart-1  
    end

    lmask, rmask = _inside_block(f.data[max(1, sid)], f.offset[max(1, sid)], rstart-1), 
        _inside_block(f.data[min(eid, ldata)], f.offset[min(eid, ldata)], rend+1)

    if rmask && lmask
    	bid, off = sid, f.offset[sid]
    	rid = eid
    	rblk = f.data[bid]
    	resize!(rblk, rend-off)
    	append!(rblk, f.data[rid])
    	_deleteat!(f.data, rid)
    	_deleteat!(f.offset, rid)
    	return rstart:rend
    elseif lmask != 0
    	bid, off = sid, f.offset[sid]
    	rblk = f.data[bid]
    	resize!(rblk, rend-off)
    	return rstart:rend
    elseif rmask != 0
    	v = C(undef, rend-rstart+1)
    	bid, off = eid, f.offset[eid]
    	lblk = f.data[bid]
    	append!(v, lblk)
    	f.data[bid] = v
    	f.offset[bid] = rstart-1
    	return rstart:rend
    end

    new_block = C(undef, rend - rstart + 1)
    insert!(f.data, eid, new_block)
    insert!(f.offset, eid, rstart-1)
    blockid = length(f.data)

    return rstart:rend
end

function get_block(f::FragmentVector{T}, i) where T
	id = _new_block_idx(f.offset, i)
	return f.data[id]
end
function get_offset(f::FragmentVector, i)
	id = _new_block_idx(f.offset, i)
	return f.offset[id]
end
function get_block_and_offset(f::FragmentVector, i)
	id = _new_block_idx(f.offset, i)
	return f.data[id], f.offset[id]
end

###################################################### HELPERS ######################################################

_length(v::AbstractVector) = length(v)
_length(v::Tuple) = length(v)
_length(n) = 1

function _inside_block(d, off, i)
	return length(d) >= i-off > 0
end
function _outside_block(d, off, i)
	return length(d) < i-off
end

function _fuse_block!(dest, src)
	append!(dest, src)
end

function _search_index(map, i)
	isempty(map) && return 0

	m = min(i, length(map))

	while m > 0 && iszero(map[m]) 
		m -= 1
	end

	iszero(m) && return m
	return map[m]
end 

function _deleteat!(v, i)
	l = length(v)

	if i != l
		v[i] = v[i+1]

		for j in i+1:l-1
			v[j] = v[j+1]
		end
    end

	pop!(v)
end

_isvalid(map, i) = iszero(map, i)