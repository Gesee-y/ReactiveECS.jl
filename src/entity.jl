##################################################################################################################
###################################################   ENTITY   ###################################################
##################################################################################################################

#################################################### Exports #####################################################

export Entity
export get_id, get_positions, get_position

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
struct Entity
	id::Int # This will help us when we will free entity, this id will be marked as available
	positions::Dict{BitType,Int} # This will help when we will do swap removal
	world::WeakRef # Avoid us the need to always pass the manager around
	components::NamedTuple # Contain the components's names and type of the entity

	## Constructor

	Entity(id::Int, world, components) = new(id, Dict{BitType,Int}(), WeakRef(world), components)
end

############################################### Accessor functions ################################################

"""
    get_id(e::Entity)

Return the `id` of the entity, i.e its position in the global data
"""
get_id(e::Entity)::Int = getfield(e, :id)

"""
    get_positions(e::Entity)::Dict{BitType,Int}

This function returns the dict of positions of the entity, which contains the index of the entity in each archetype
"""
get_positions(e::Entity)::Dict{BitType,Int} = getfield(e, :position)

"""
    get_position(e::Entity, archetype::BitType)::Int

This function returns the position of a entity in an `archetype`
"""
get_position(e::Entity, archetype::BitType)::Int = get_positions(e)[archetype]

Base.show(io::IO, e::Entity) = show(io, "Entity $(get_id(e))")
Base.show(e::Entity) = show(stdout, e)