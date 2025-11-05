############################################################################################################################################################################
################################################################################## SoA LAYOUT ##############################################################################
############################################################################################################################################################################

struct SoALayout{T} <: AbstractArrayLayout{T}
	data::StructVector{T}

	## Constructors

	SoALayout{T}(::UndefInitializer, n) where T = new{T}(StructVector{T}(undef, n))
	SoALayout{T}() where T = SoALayout{T}(undef, 0)
end

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