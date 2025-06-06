################################################## Entity component system ################################################

module EDECS

export AbstractEntity, AbstractComponent, AbstractSystem
export add_entity!, remove_entity!, attach_component!, detach_component!
export subscribe!, run!, run_system!, get_component

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
	components::Dict{Symbol, AbstractComponent}
end

# TODO : Search better data structures to keep data ain the ECS manager, it may improve performances
mutable struct ECSManager{T}
	entities::Dict{UInt, T}
	groups::Dict{Tuple, Vector{T}} # We prefer a vector to a dict, it's easier to parallelise
	systems::Dict{Tuple, Vector{AbstractSystem}}
	chunk_count::Int # Used for partitioning

	ECSManager{T}() where T <: AbstractEntity = new{T}(
		Dict{UInt,T}(), 
		Dict{Tuple, Vector{UInt}}(),
		Dict{Tuple, Vector{AbstractSystem}}(),
		1)
end


"""
    add_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity

This add an entity to the ECS and sort it in the existing archetype
"""
function add_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity
	ecs.entities[entity.id] = entity
	
	for archetype in keys(ecs.groups)
		if _match_archetype(entity, archetype)
			push!(ecs.groups[archetype], entity)
		end
	end

end

"""
    remove_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity

This remove an entity to the ECS and remove it in the existing archetype where he is.
"""
function remove_entity!(ecs::ECSManager, entity::T) where T <: AbstractEntity
	delete!(ecs.entities, entity.id)
	_remove_entity_in_groups(ecs, entity)
end

function attach_component!(ecs::ECSManager{T}, entity::T, component::AbstractComponent) where T <: AbstractEntity
	
	# First of all, we add the component to the entity
    entity.components[get_name(component)] = component

    # If the entity is already registered in the ECS manager
	if haskey(ecs.entities,entity.id)

		for archetype in keys(ecs.groups)
			if _match_archetype(entity,archetype) && !(entity.id in ecs.groups[archetype])
				push!(ecs.groups[archetype], entity)
			end
		end
		
	end
end

function detach_component!(ecs::ECSManager{T}, entity::T, component::AbstractComponent) where T <: AbstractEntity
	name = get_name(component)
	delete!(entity.components,name)
	if entity.id in ecs.entities
		_remove_entity_in_groups(ecs, entity)
	end
end

############################################## Systems ##################################################

function subscribe!(ecs::ECSManager{T},system::AbstractSystem, archetype::Tuple) where T
	if !haskey(ecs.groups, archetype)
		ecs.systems[archetype] = AbstractSystem[system]
		ecs.groups[archetype] = UInt[]
		for entity in values(ecs.entities)
			if _match_archetype(entity, archetype)
				push!(ecs.groups[archetype], entity)
			end
		end
	else
		push!(ecs.systems[archetype], system)
	end

	return nothing
end

run!(::AbstractSystem, batch) = batch

function run_system!(system::AbstractSystem)

	# We skip the error checking on purpose
	# Just taking data, extremely low risk of error
	@async while system.active
		batch = take!(system.flow.input)
		run!(system, batch)
	end
end

include("flow.jl")

############################################ Components ##################################################

get_component(entity::AbstractEntity, ::Type{T}) where T <: AbstractComponent = entity.components[get_name(T)]::T
get_component(entity::AbstractEntity, ::T) where T <: AbstractComponent = get_component(entity, T)

get_name(::Type{T}) where T <: AbstractComponent = Symbol(T.name.name)
get_name(::T) where T <: AbstractComponent = get_name(T)

############################################# Helpers ####################################################

_match_archetype(entity::AbstractEntity, archetype::Tuple) = return all(c -> haskey(entity.components,c), archetype)

function _remove_entity_in_groups(ecs::ECSManager, entity::AbstractEntity)
	for k in keys(ecs.groups)
		if !_match_archetype(entity,k) && entity.id in ecs.groups[k]
			filter!(x -> x !== entity, ecs.groups[k])
		end
	end
end

end # Module
