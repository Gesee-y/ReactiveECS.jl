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
	ID::Int64
    alive::Bool
    parentID::MInt64
	archetype::UInt128
	world::WeakRef
    children::Vector{MInt64}

    ## Constructors

    Entity(id::Int, archetype::Integer, ref; parentID=MInt64(-1)) = new(id, true, parentID, 
        archetype, ref, MInt64[])

    Entity(e::Entity; parentID=MInt64(-1)) = new(get_id(e), true, parentID, e.archetype, e.world, MInt64[])
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

#=function Base.getproperty(e::Entity, s::Symbol)
    s in getfield(e, :components) || return getfield(e, s)
    column = get_component(getfield(e, :world).value, s)
    return ComponentWrapper(get_id(e), WeakRef(column))
end
function Base.setproperty!(e::Entity, v, s::Symbol)
    s in getfield(e, :components) || return setfield!(e, v, s)
    column = get_component(e.world.value, s)
    column[get_id(e)[]] = v
end

function Base.getproperty(c::ComponentWrapper, s::Symbol)
    column = getfield(c, :column).value
    return getproperty(column, s)[getfield(c, :id)[]]
end
function Base.setproperty!(c::ComponentWrapper, v, s::Symbol)
    column = getfield(c, :column).value
    return getproperty(column, s)[getfield(c, :id)[]] = v
end
=#
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
    print_tree(io::IO,n::Entity;decal=0,mid=1,charset=get_charset())

This will print to `io` the tree representation of the parent-child relationships starting from the entity `e`.
`decal` is the actual number indentation (used to make a full tree).
`mid` serve to indicate if there should be a midpoint symbol in the representation.
`charset` is the set of character used to print the tree. See `TreeCharSet`.
"""
function NodeTree.print_tree(io::IO,n::Entity;decal=0,mid=1,charset=get_charset())
    childrens = get_children(n)
    tree = get_tree(n)

    print(typeof(n)," : ")
    print(nvalue(n))

    for i in eachindex(childrens)
        println()
        child = get_node(tree,childrens[i])

        for i in 1:decal+1
            i > mid && print(charset.midpoint)
            print(charset.indent)
        end

        if i < length(childrens) && !(decal-1>0)
            print(charset.branch)
        elseif !(decal-1>0)
            print(charset.terminator)
        end
        print(io,charset.link)

        print_tree(io,child;decal=decal+1,mid=(decal+1) + Int(i==length(childrens)))
    end
end

"""
    get_id(e::Entity)

Return the `id` of the entity, i.e its position in the global data
"""
@inline get_id(e::Entity) = getfield(e, :ID)
