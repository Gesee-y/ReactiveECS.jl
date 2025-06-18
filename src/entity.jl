##################################################################################################################
###################################################   ENTITY   ###################################################
##################################################################################################################

#################################################### Exports #####################################################

export Entity
export get_id, get_positions, get_position, get_component

###################################################### Core ######################################################

"""
    struct Entity
		id::Int
		positions::Dict{BitType,Int}
		world::WeakRef
		components::NamedTuple

This struct represent an entity for the ECS. An entity is just an `id`, which is his position in the global data
the `positions` field is the index of the entity in the different archtype group.
`world` is a weak reference to the manager object.
"""
mutable struct Entity
	id::Int # This will help us when we will free entity, this id will be marked as available
	positions::LittleDict{BitType,Int} # This will help when we will do swap removal
	world::WeakRef # Avoid us the need to always pass the manager around
	components::Tuple # Contain the components's type of the entity

	## Constructor

	Entity(id::Int, world, components) = new(id, LittleDict{BitType,Int}(), WeakRef(world), components)
end

mutable struct EntityInterval
	id::Int
	num::Int
	archetypes::Tuple
end

"""
    struct ComponentWrapper
		id::Int
		data::WeakRef
		obj::Symbol

This struct serve to return you the correct component when you request it with get or set property
"""
struct ComponentWrapper
	id::Int
	data::WeakRef
	obj::Symbol
end

############################################### Accessor functions ################################################

Base.getproperty(e::Entity,s::Symbol) = s in fieldnames(Entity) ? getfield(e, s) : get_component(e, s)

#Base.setproperty!(e::Entity,s::Symbol) = ComponentWrapper(get_id(e), WeakRef(e.world.value.world_data), s, v)
#@generated Base.setproperty!(c::ComponentWrapper,v, s::Symbol) = :(getfield(c,:data).value[getfield(c,obj)].s[getfield(c,:id)] = getfield(c,:v))

"""
    get_world()

This function returns the current world. It should be overrided to return you ECSManager
"""
get_world() = error("The World hasn't been defined yet.")

"""
    get_id(e::Entity)

Return the `id` of the entity, i.e its position in the global data
"""
@inline get_id(e::Entity)::Int = getfield(e, :id)

"""
    get_positions(e::Entity)::Dict{BitType,Int}

This function returns the dict of positions of the entity, which contains the index of the entity in each archetype
"""
@inline get_positions(e::Entity)::Dict{BitType,Int} = getfield(e, :position)

"""
    get_position(e::Entity, archetype::BitType)::Int

This function returns the position of a entity in an `archetype`
"""
@inline get_position(e::Entity, archetype::BitType)::Int = get_positions(e)[archetype]

@inline get_component(e::Entity, s::Symbol) = e.world.value != nothing ? view(get_component(e.world.value, s), e.id) : error("The entity hasn't been added to the manager yet.")

Base.show(io::IO, e::Entity) = show(io, "Entity $(get_id(e))")
Base.show(e::Entity) = show(stdout, e)
