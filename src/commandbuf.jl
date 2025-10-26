###########################################################################################################################################
####################################################################### COMMAND BUFFER ####################################################
###########################################################################################################################################
@enum ECSCommandType begin
	ADD_ENTITY
	REM_ENTITY
	ADD_COMPONENT
	REM_COMPONENT
end

abstract type ECSCommand end

struct AddEntityCmd{T,V} <: ECSCommand
	comp::T
	value::V

	## Constructors

	AddEntityCmd(key::T) where T <: Tuple = new{T,Nothing}(key)
	AddEntityCmd(key::T, val::V) where {T <: Tuple, V <: NamedTuple} = new{T,V}(key, val)
end

struct DelEntityCmd <: ECSCommand
	id::MInt
	arch::UInt128
end

struct AddCompCmd{T} <: ECSCommand
	id::MInt
	old_arch::UInt128
	comp::T

	## Constructors

	AddCompCmd(id, old, c::T) where T <: AbstractComponent = new{T}(id, old, c)
	AddCompCmd(id, old, c::T) where T = new{T}(id, old, c)
end

struct DelCompCmd <: ECSCommand
	id::MInt
	old_arch::UInt128
	comp::Symbol

	## Constructors

	DelCompCmd(id, old, c) = new(id, old, c)
end

