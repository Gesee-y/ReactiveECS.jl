############################################################################################################################################
############################################################### SPARSESET IMPLEMENTATION ###################################################
############################################################################################################################################

using SparseArrays

struct SparseSet{T,V}
	inds::SparseVector{T,T}
	vals::Vector{V}

	## Constructors

	SparseSet{T,V}(size) where {T,V} = new{T,V}(SparseVector{T,T}(undef, size), V[])
end

############################################################ OPERATIONS ###################################################################

function Base.getindex(s::SparseSet, i)
	ind = s.inds[i]
	@boundscheck iszero(ind) && error("SparseSet doesn't have a value at index $i")
	return s.vals[ind]
end

function Base.setindex!(s::SparseSet, v, i)
	ind = s.inds[i]
	vals = s.vals
	if iszero(ind)
		s.inds[i] = length(vals)+1
		push!(vals, v)
		return
	end
	
	vals[ind] = v
	return
end

hasindex(s::SparseSet, i) = !iszero(s.inds[i])
