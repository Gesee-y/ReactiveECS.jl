#########################################################################################################################
###################################################### ENTITY ###########################################################
#########################################################################################################################

###################################################### Exports ##########################################################

export Entity
export get_id

######################################################## Core ###########################################################

"""
    mutable struct Entity
		ID::UInt
		archetype::UInt
		components::Tuple
		world::WeakRef

This struct represent an entity for the ECS. An entity is just an `ID`, which is his position in the global data
`archetype` is the set of components the entity possess.
`components` is the name of the components that the entity have.
`world` is a weak reference to the manager object.
"""
mutable struct Entity <: AbstractEntity
	ID::Int64
    alive::Bool
	archetype::UInt128
	world::WeakRef

    ## Constructors

    Entity(id::Int, archetype::Integer, ref;) = new(id, true, 
        archetype, ref)

    Entity(e::Entity) = new(get_id(e), true, e.archetype, e.world)
end

struct ComponentWrapper
    id::MInt64
    column::WeakRef
end

##################################################### Operations ########################################################

Base.show(io::IO, e::Entity) = print(io, "Entity(id=$(e.ID[]), alive=$(e.alive))")
Base.show(e::Entity) = show(stdout, e)
setid!(e::Entity, id::Int) = setfield!(e, :ID, id)
setarchetype!(e::Entity, arch) = setfield!(e, :archetype, arch)
Base.getindex(e::Entity) = e.ID & 0xffffffff
ECSInterface.is_alive(e::Entity) = e.alive

"""
    get_id(e::Entity)

Return the `id` of the entity, i.e its position in the global data
"""
@inline get_id(e::Entity) = getfield(e, :ID)
