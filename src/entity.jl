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
	const id::Int # This will help us when we will free entity, this id will be marked as available
	const world::WeakRef # Avoid us the need to always pass the manager around
	components::Tuple # Contain the components's type of the entity
	parent::Int
	children::Vector{Int}
	## Constructor

	Entity(id::Int, world, components; parent=-1) = new(id, WeakRef(world), components, parent, Int[])
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
	data::VirtualStructArray
end
############################################### Accessor functions ################################################

# We start by overloading the NodeTree interface

NodeTree.get_tree(e::Entity) = e.world.value
NodeTree.get_root(e::Entity)::Vector{Int} = !isnothing(e.world.value) ? get_root(get_tree(e)) : error("The entity hasn't been added to the manager yet.")
NodeTree.add_child(e::Entity, e2::Entity) = begin
    push!(get_children(e), get_id(e2))
    e2.parent = get_id(e)
end
NodeTree.remove_child(e::Entity, e2::Entity) = begin
    children = get_children(e)
    id = get_id(e2)
    for i in eachindex(children)
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
NodeTree.get_children(e::Entity)::Vector{Int} = getfield(e, :children)
NodeTree.get_nodeidx(e::Entity)::Int = get_id(e)

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

Base.getproperty(e::Entity,s::Symbol) = s in fieldnames(Entity) ? getfield(e, s) : get_component(e, s)
function Base.setproperty!(e::Entity,s::Symbol,v)
	world = e.world.value 
    if world != nothing
    	data = get_component(world, s)
    	data.dirty[id] = true
        id = get_id(e)
    	data[id] = v
    else
    	error("The entity hasn't been added to the manager yet.")
    end
end

function Base.getproperty(c::ComponentWrapper, s::Symbol)
	data = getfield(c,:data)
	id = getfield(c,:id)
	return getproperty(data, s)[id]
end
function Base.setproperty!(c::ComponentWrapper, s::Symbol,v)
	data = getfield(c,:data)
	id = getfield(c,:id)
	data.dirty[id] = true
	getproperty(data, s)[id] = v
end

@generated function Base.getindex(c::ComponentWrapper, s::Symbol)
	println(c.parameters)
	params = c.parameters[3].parameters
	key = params[1]
	types = params[2].parameters
	types_tuple = NamedTuple{key}(types)
    
    return quote
    	id = getfield(c, :id)
		data::getproperty($types_tuple, s) = getproperty(getfield(c,:data), s)
		data[id]
	end
end
function Base.setproperty!(c::ComponentWrapper, v, s::Symbol)
	data = getfield(c,:data)
	id = getfield(c,:id)

	getproperty(data, s)[id] = v
end 

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

get_component(e::Entity, s::Symbol) = begin
    world = e.world.value 
    if world != nothing
    	data = get_component(world, s)
    	return ComponentWrapper(get_id(e), data)
    else
    	error("The entity hasn't been added to the manager yet.")
    end
end
Base.show(io::IO, e::Entity) = show(io, "Entity $(get_id(e))")
Base.show(e::Entity) = show(stdout, e)

############################################################ Helpers ##############################################################
