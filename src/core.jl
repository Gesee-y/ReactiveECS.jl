################################################## Core System ########################################

export AbstractComponent, AbstractSystemData, AbstractArchetype
export System, @system, BitArchetype, Entity, ECSManager

const SYS_CHANNEL_SIZE = Inf

"""
    abstract type AbstractEntity

Abstract type to represent a generic entity
"""
abstract type AbstractEntity end

"""
    abstract type AbstractComponent

Abstract type to represent a generic component. When you create custom element, you should derive from this type
"""
abstract type AbstractComponent end

"""
    abstract type AbstractSystemData

Abstract type to represent a generic system's data
"""
abstract type AbstractSystemData end

abstract type AbstractSystem end

"""
    abstract type AbstractArchetype

Define and Abstract type of archetype. You should derive this if you want to store archtypes your own way
You should also define `+` for adding component and `-` for removing component from the archetype
The constructor should follow accept a tuple of component or a component alone and a no argument constructor
"""
abstract type AbstractArchetype end

"""
    struct BitArchetype
    	value::UInt128

This define an archetype based on bitset. can take 128 components max but is extremely fast. 
"""
struct BitArchetype <: AbstractArchetype
	value::UInt128

	## Constructors

	BitArchetype(c) = new(get_bits(c))
	BitArchetype(t::Tuple) = new(sum(get_bits.(t)))
	BitArchetype() = new(UInt128(0))
end
Base.:+(b1::BitArchetype, b2::BitArchetype) = BitArchetype(b1.value | b2.value)
Base.:-(b1::BitArchetype, b2::BitArchetype) = BitArchetype(xor(b1.value, b2.value))

"""
    mutable struct Entity{A} <: AbstractEntity
		const id::UInt
		valid::Bool
		archetype::A
		components::NamedTuple

Struct representing an entity that support archetype of type `A`, see `AbstractArchetype for more information`
"""
mutable struct Entity{A} <: AbstractEntity
	id::UInt
	archetype::A
	components::NamedTuple
	positions::Dict{A,Int}
	world_pos::Dict{Symbol,Int}
	world::WeakRef
end
## Outer Constructors
Entity(T::Type{<:AbstractArchetype}, args...; kwargs...) = error("Entity doesn't support archetype of type $T yet")
Entity(id::Integer;kwargs...) = Entity(BitArchetype, id; kwargs...)
function Entity(::Type{BitArchetype}, id::Integer;kwargs...)
    components = NamedTuple(kwargs)
    archetype = BitArchetype(sum(get_bits.(values(components))))
    Entity{BitArchetype}(id, archetype, components, Dict{BitArchetype,Int}(), Dict{Symbol,Int}(), WeakRef(nothing))
end

"""
    @system sys_name

This macro serve to create a new system . You can initialize it with just `sys_name()`.
"""
macro system(name)
	return quote
		mutable struct $name{A} <: AbstractSystem
			active::Bool
			archetype::A
			flow::Channel{Tuple{WeakRef, WeakRef}}
			children::Vector{AbstractSystem}
			
			## Constructors

			$name{A}() where A <: AbstractArchetype = new(true,A(), Channel{Tuple{WeakRef, WeakRef}}(SYS_CHANNEL_SIZE), AbstractSystem[])
			$name() = $name{BitArchetype}()
		end
	end
end

mutable struct DataView
	positions::SoA
	data::StructArray
end

mutable struct ComponentData
	ids::Vector{WeakRef}
	data::StructArray
end
Base.push!(c::ComponentData, t::Tuple) = (push!(c.ids, t[1]); push!(c.data, t[2]))
Base.pop!(c::ComponentData) = (pop!(c.ids), pop!(c.data))
Base.getindex(c::ComponentData, i::Int) = i == 1 ? getfield(c,:ids) : getfield(c,:data)

"""

"""
mutable struct ECSManager{A}
	entities::Dict{UInt, Entity{A}}
	components::Dict{Symbol,ComponentData}
	groups::Dict{A, aSoA}
	systems::Dict{A, Vector{AbstractSystem}}
	
	ECSManager{A}() where A <: AbstractArchetype = new{A}(
		Dict{UInt,Entity{A}}(),
		Dict{Symbol,ComponentData}(),
		Dict{A, aSoA}(),
		Dict{A, Vector{AbstractSystem}}()
		)
end