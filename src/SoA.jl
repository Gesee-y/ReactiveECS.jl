######################################################## Struct of Array #####################################################

export SoA, aSoA

abstract type AbstractSoA{T} end

#=
    We first need a way to initialize the different array
=#

mutable struct SoA{T} <: AbstractSoA{T}
	data::NamedTuple

	## Constructor

	function SoA{T}(names::Tuple{Vararg{Symbol}}) where T <: Tuple
		types = Tuple(T.parameters)
		@assert length(names) == length(types) "names should have the same length as types"

		data = map(Ty -> StructArray{Ty}(undef,0), types)

		return new{T}(NamedTuple{names}(data))
	end
	function SoA{T}(names::Tuple{Vararg{Symbol}}, data::Vector{StructArray}) where T <: Tuple
		types = Tuple(T.parameters)
		@assert length(names) == length(types) == length(data) "names should have the same length as types and data"

		return new{T}(NamedTuple{names}(data))
	end
end

mutable struct aSoA{T} <: AbstractSoA{T}
	data::NamedTuple

	## Constructor

	function aSoA{T}(names::Tuple{Vararg{Symbol}}) where T <: Tuple
		types = Tuple(T.parameters)
		@assert length(names) == length(types) "names should have the same length as types"

		data = map(Ty -> Ty[], types)

		return new{T}(NamedTuple{names}(data))
	end
	function aSoA{T}(names::Tuple{Vararg{Symbol}}, data::Vector{Vector}) where T <: Tuple
		types = Tuple(T.parameters)
		@assert length(names) == length(types) == length(data) "names should have the same length as types and data"

		return new{T}(NamedTuple{names}(data))
	end
end

function Base.getindex(S::AbstractSoA, i::Int)
	1 <= i <= length(S.data[1]) || throw(BoundsError("Trying to access SoA at index $i"))
	return map(A -> A[1], S.data)
end

function Base.setindex!(S::aSoA, data::Tuple, i::Int)
	1 <= i <= length(S.data[1]) || throw(BoundsError("Trying to access SoA at index $i"))
	for j in eachindex(S.data[1])
		S.data[j][i] = data[j]
	end
end
function Base.setindex!(S::aSoA, data::NamedTuple, i::Int)
	1 <= i <= length(S.data[1]) || throw(BoundsError(S,i))
	key = keys(data)
	for k in key
		S.data[k][i] = data[k]
	end
end

Base.length(S::AbstractSoA) = length(S.data[1])
Base.size(S::AbstractSoA) = (length(S), )

function Base.push!(S::AbstractSoA{T}, data::T) where T <: Tuple
	for i in eachindex(S.data[1])
		push!(S.data[i], data[i])
	end
end

function Base.push!(S::AbstractSoA{T}, data::Union{AbstractDict,NamedTuple}) where T <: Tuple
	for key in keys(S.data)
		if key in keys(data)
		    push!(S.data[key], data[key])
		end
	end
end
function Base.append!(S::SoA{T}, data::NamedTuple) where T <: Tuple
	for key in keys(S.data)
		append!(S.data[key], data[key])
	end
end

function Base.view(S::SoA{T}, idx::Vector{Int}) where T <: Tuple
	L = length(S.data)
	data = Vector{StructArray}(undef,L)
	for i in Base.OneTo(L)
		data[i] = view(S.data[i], idx)
	end

	return SoA{T}(keys(S.data), data)
end
function Base.view(S::SoA{T}, idx::UnitRange) where T <: Tuple
	Sdata::NamedTuple = S.data
	L::Int = length(Sdata)
	data::Vector{StructArray} = Vector{StructArray}(undef,L)
	@inbounds for i in 1:L
		data[i] = view(Sdata[i], idx)::StructArray
	end

	return SoA{T}(keys(Sdata), data)
end



Base.pop!(S::AbstractSoA) = map(A -> pop!(A), S.data)

Base.iterate(S::AbstractSoA, i::Int=1) = i <= length(S) ? S[i] : nothing
Base.eachindex(S::AbstractSoA) = Base.OneTo(length(S))