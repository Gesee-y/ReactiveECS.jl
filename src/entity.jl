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
mutable struct Entity
	ID::Int
	archetype::UInt128
	components::Tuple
	world::WeakRef
end

##################################################### Operations ########################################################

"""
    get_tree(e::Entity)

This return the tree the entity belongs to.
If the entity has not been added yet to the ECSManager, it will return nothing
"""
NodeTree.get_tree(e::Entity) = e.world.value

"""
    get_root(e::Entity)

Return a vector of the entites at the root of the tree of the entity `e`.
Throws an error if the entity hasn't been added to the ECSManager yet.
"""
NodeTree.get_root(e::Entity)::Vector{Int} = !isnothing(e.world.value) ? get_root(get_tree(e)) : error("The entity hasn't been added to the manager yet.")

"""
    add_child(e::Entity, e2::Entity)

Add the entity `e2` as the child of the entity `e`.
An entity can only have one parent, if the entity `e2` already has a parent, nothing will happen.
"""
NodeTree.add_child(e::Entity, e2::Entity) = begin
    
    # If e2's parent ID is less than one, then he don't have a parent yet
    if e2.parent < 1
	    push!(get_children(e), get_id(e2))
	    e2.parent = get_id(e)
	end
end

"""
    remove_child(e::Entity, e2::Entity)

Remove the entity `e2` from the children of `e`.
The entity can then be the child of any other node.

    remove_child(e::Entity, i::Int)

Remove the i-th child of `e`.
Throws an error if `i` exceed the number of childre of `e`.
    
    remove_child(children::Vector{Int}, e2::Entity)

Remove the `ID` of the entity `e` from the vector `children`. 
"""
NodeTree.remove_child(e::Entity, e2::Entity) = begin
    children = get_children(e)
    id = get_id(e2)
    @inbounds for i in eachindex(children)
    	
    	# The children matching the id of e2 will get removed
    	if children[i] == id
    		children[i] = pop!(children)
    		return
    	end
    end
end
NodeTree.remove_child(children::Vector{Int}, e2::Entity) = begin
    id = get_id(e2)
    for i in eachindex(children)
    	if children[i] == id
    		children[i] = pop!(children)
    		return
    	end
    end
end
NodeTree.remove_child(e::Entity, i::Int) = begin
    children = get_children(e)
    children[i] = pop!(children)
end

"""
    get_children(e::Entity)

Return a vector of ints, corresponding to the index of the entities children of `e`.
"""
NodeTree.get_children(e::Entity) = getfield(e, :children)

"""
    get_nodeidx(e::Entity)

Return the index of the entity in the list of entities.
Behave exactly as `get_id`.
"""
NodeTree.get_nodeidx(e::Entity) = get_id(e)

"""
    get_id(e::Entity)

Return the `id` of the entity, i.e its position in the global data
"""
@inline get_id(e::Entity) = getfield(e, :ID)
