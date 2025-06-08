################################################## Entity component system ################################################

module EDECS

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
    abstract type AbstractSystem

Abstract type to represent a generic system
"""
abstract type AbstractSystem end

mutable struct Entity <: AbstractEntity
	const id::UInt
	valid::Bool
	archetype::UInt128
	components::NamedTuple

	## Constructors
	Entity(id::Integer,valid=false;kwargs...) = begin
	    components = NamedTuple(kwargs)
	    archetype = get_bits(values(components))
	    new(id, valid, archetype, components)
	end
end

mutable struct ECSManager{T}
	entities::Dict{UInt, T}
	groups::Dict{UInt128, Vector{WeakRef}} # We prefer a vector to a dict, it's easier to parallelise
	systems::Dict{UInt128, Vector{AbstractSystem}}
	
	ECSManager{T}() where T <: AbstractEntity = new{T}(
		Dict{UInt,T}(), 
		Dict{UInt128, Vector{WeakRef}}(),
		Dict{UInt128, Vector{AbstractSystem}}()
		)
end


"""
    add_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity

This add an entity to the ECS and sort it in the existing archetype
"""
function add_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity
	ecs.entities[entity.id] = entity
	entity.valid = true
	
	for archetype in keys(ecs.groups)
		if _match_archetype(entity, archetype)
			push!(ecs.groups[archetype], WeakRef(entity))
		end
	end

end

"""
    remove_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity

This remove an entity to the ECS and remove it in the existing archetype where he is.
"""
function remove_entity!(ecs::ECSManager, entity::T) where T <: AbstractEntity
	delete!(ecs.entities, entity.id)
	entity.valid = false
end

function attach_component!(ecs::ECSManager{T}, entity::T, component::AbstractComponent) where T <: AbstractEntity
	
	# First of all, we replace the old component to put a new one containint the new component
	name=get_name(component)
    entity.components = NamedTuple{(keys(entity.components...,name))}((values(entity.components)..., component))

    # If the entity is already registered in the ECS manager
	if haskey(ecs.entities,entity.id)

		for archetype in keys(ecs.groups)
			if _match_archetype(entity,archetype) && !(entity.id in ecs.groups[archetype])
				push!(ecs.groups[archetype], WeakRef(entity))
			end
		end
		
	end
end

function detach_component!(ecs::ECSManager{T}, entity::T, component::AbstractComponent) where T <: AbstractEntity
	name = get_name(component)
	entity.components = _delete_tuple(entity.components, name)

	if entity.id in ecs.entities
		_remove_entity_in_groups(ecs, entity)
	end
end

"""
    validate(ref::WeakRef, i::Int)

This function should be used inside the run! function of a system, it will check the validity of an entity and return it
"""
function validate(ref::WeakRef, i::Int)
	entities = ref.value
	entity = entities[i]
	if isnothing(entity) || !(entity.value.valid)
		lck = ReentrantLock()
		
		# We ensure that this sytem is the only one suppressing invalid data
		lock(lck)

		# We do a swap deletion
		tmp = pop!(entities)
		entities[i] = tmp

		# We unlock the process
		unlock(lck)
	end

	return entity.value
end

############################################## Systems ##################################################

function subscribe!(ecs::ECSManager{T},system::AbstractSystem, components::Tuple) where T
	
	# If the is not system with a subscription to the given archetype
	archetype = get_bits(components)
	if !haskey(ecs.groups, archetype)
		ecs.systems[archetype] = AbstractSystem[system]
		ecs.groups[archetype] = UInt[]
		for entity in values(ecs.entities)
			if _match_archetype(entity, archetype)
				push!(ecs.groups[archetype], WeakRef(entity))
			end
		end
	else
		push!(ecs.systems[archetype], system)
	end

	return nothing
end

function run_system!(system::AbstractSystem)

	# We skip the error checking on purpose
	# Just taking data, extremely low risk of error
	errormonitor(@async while system.active
			batch = take!(system.flow.input)
			res = run!(system, batch)
			children = get_children(system)
			
			if res != nothing
				for child in children
					put!(child.flow.input, res)
				end
			end
		end)
end

include("flow.jl")

############################################ Components ##################################################

get_component(entity::AbstractEntity, ::Type{T}) where T <: AbstractComponent = entity.components[get_name(T)]::T
get_component(entity::AbstractEntity, ::T) where T <: AbstractComponent = get_component(entity, T)

get_name(::Type{T}) where T <: AbstractComponent = Symbol(T.name.name)
get_name(::T) where T <: AbstractComponent = get_name(T)

get_type(T::Type) = T

get_bits(c::AbstractComponent) = get_bits(typeof(c))
get_bits(t::Tuple) = +(get_bits.(t)...)
get_bits(::Type{T}) where T = 0b0

############################################# Helpers ####################################################

_match_archetype(entity::AbstractEntity, archetype::Tuple) = _match_archetype(entity, get_bits(archetype)) 
_match_archetype(entity::AbstractEntity, archetype::Unsigned) = (entity.archetype & archetype) == archetype

function _remove_entity_in_groups(ecs::ECSManager, entity::AbstractEntity)
	for k in keys(ecs.groups)
		if !_match_archetype(entity,k) && entity.id in ecs.groups[k]
			filter!(x -> x !== entity, ecs.groups[k])
		end
	end
end

function _delete_tuple(t::NamedTuple, c::Symbol)
	f = findfirst(x -> x==c, keys(t))
	return NamedTuple{(keys(t[begin:f-1])...,keys(t[f+1:end])...)}((values(t[begin:f-1])..., values(t[f+1:end])))
endend # Module
