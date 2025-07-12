##########################################################################################################################
#################################################### MUTABLE INTEGERS ####################################################
##########################################################################################################################


######################################################### CORE ###########################################################

"""
    mutable struct MInt{T} <: Signed
		value::T

Mutable integers. Useful when you need integers referenced across multiple data effectively.
Actually support arithmetic operations.

## Constructors

    MInt{T}(n::Integer) where T <: Signed

Create a new `MInt` with data of type `T`. This will convert `n` to type `T`

    MInt(n::T) where T <: Signed

This create a new MInt of type `T`.
"""
mutable struct MInt{T} <: Signed
	value::T

	## Constructors

	MInt{T}(n::Integer) where T <: Signed = new{T}(convert(T,n))
	MInt(n::T) where T <: Signed = new{T}(n)
end

const MInt8 = MInt{Int8}
const MInt16 = MInt{Int16}
const MInt32 = MInt{Int32}
const MInt64 = MInt{Int64}
const MInt128 = MInt{Int128}

###################################################### OPERATIONS ########################################################

Base.getindex(n::MInt) = getfield(n, :value)
Base.setindex(n::MInt, v::Integer) = setfield(n, :value, v)
Base.isequal(n1::MInt, n2::MInt) = n1[] == n2[]
Base.isless(n1::MInt, n2::MInt) = n1[] < n2[]