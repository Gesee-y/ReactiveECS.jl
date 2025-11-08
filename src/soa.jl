############################################################################################################################################################################
################################################################################## SoA LAYOUT ##############################################################################
############################################################################################################################################################################

struct SoALayout{T} <: AbstractArrayLayout{T}
	data::StructVector{T}

	## Constructors

	SoALayout{T}(::UndefInitializer, n) where T = new{T}(StructVector{T}(undef, n))
	SoALayout{T}() where T = SoALayout{T}(undef, 0)
end

struct EntityIndexing <: FragmentIndexingStyle end

@generated function Base.setindex!(s::SoALayout{T}, v, i) where T
	expr = Expr(:block)
	fields, types = fieldnames(T), fieldtypes(T)
	push!(expr.args, :(data = FragmentArrays._getdata(s)))
	for j in eachindex(fields)
		data = gensym()
		k, t = fields[j], types[j]
		push!(expr.args, quote
			$data::Vector{$t} = data.$k
		    $data[i] = v.$k
		end)
	end

	return expr
end

function Base.getindex(f::FragmentVector{T,C,EntityIndexing}, i) where {T, C}
	id, j = i >> 32, i & 0xffffffff
	return f.data[id][j - f.offset[id]]
end

function Base.setindex!(f::FragmentVector{T,C,EntityIndexing}, v, i) where {T, C}
	id, j = i >> 32, i & 0xffffffff
	return f.data[id][j - f.offset[id]] = v
end

function defgetindex(f::FragmentVector, i)
	idx = FragmentArrays._new_block_idx(f.offset, i)
    @boundscheck 0 < idx || error("")

    blk, off = f.data[idx], f.offset[idx]
    
    @boundscheck FragmentArrays._outside_block(blk, off, i) && error("")

    return @inbounds blk[i-off]
end
function defsetindex!(f::FragmentVector, v, i)
	idx = FragmentArrays._new_block_idx(f.offset, i)
    0 < idx || return insert!(f, i, v)

    blk, off = f.data[idx], f.offset[idx]
    
    FragmentArrays._outside_block(blk, off, i) && return insert!(f, i, v)

    return @inbounds blk[i-off] = v
end