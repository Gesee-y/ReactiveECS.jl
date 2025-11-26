############################################################################################################################################################################
################################################################################## SoA LAYOUT ##############################################################################
############################################################################################################################################################################

struct SoALayout{T} <: AbstractArrayLayout{T}
	data::T

	## Constructors

	SoALayout{T}(::UndefInitializer, n) where T = (data=StructVector{T}(undef, n); new{typeof(data)}(data))
	SoALayout{T}() where T = SoALayout{T}(undef, 0)
	SoALayout{T}(::UndefInitializer, n) where T<:StructVector = (new{T}(StructVector{T.parameters[1]}(undef, n)))
end

struct ViewLayout{T} <: AbstractArrayLayout{T}
	data::FieldViewable{T, 1, Vector{T}}

	## Constructors

	ViewLayout{T}(::UndefInitializer, n) where T = new{T}(FieldViewable(Vector{T}(undef, n)))
	ViewLayout{T}() where T = ViewLayout{T}(undef, 0)
end

struct EntityIndexing <: FragmentIndexingStyle end

Base.getproperty(v::ViewLayout, s::Symbol) = getproperty(getfield(v, :data), s)
Base.setproperty!(v::ViewLayout, val, s) = setproperty!(getfield(v, :data), val, s)

@generated function Base.setindex!(s::SoALayout{L}, v, i) where L
	expr = Expr(:block)
	T = L.parameters[1]
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
hasindex(f::FragmentVector{T,C,EntityIndexing}, i) where {T,C} = begin
    id, j = i >> 32, i & 0xffffffff
    return FragmentArrays._inside_block(f.data[id], f.offset[id], j)
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

to_layout(::Type{ViewLayout}, T) = T
to_layout(::Type{SoALayout}, T) = typeof(StructVector{T}(undef, 0))