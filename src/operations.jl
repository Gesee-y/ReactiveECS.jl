################################################ Operations for the ECS ##################################################

export add_entity!, remove_entity!, subscribe!, run_system!
export attach_component!, detach_component!
export listen_to, dispatch_data

#=
    We need to be able to have a view on the needed part of the entity
    For this, w
=#

function Base.getindex(entity::Entity)
	ecs = entity.world.value
end

"""
    add_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity

This add an entity to the ECS and sort it in the existing archetype
"""
function add_entity!(ecs::ECSManager{A}, entity::Entity{A}) where A <: AbstractArchetype
	if entity.world.value == nothing

		ecs.entities[entity.id] = entity
		entity.world = WeakRef(ecs)
		entity_components = entity.components
		
		for c in entity_components
			key = get_name(c)
			components = ecs.components

			# If there is already a list of this component in the ECS manager
			if haskey(components, key)

				# We get the length
			    entity.world_pos[key] = length(components[key][2])+1
			    
			    # And push the entity's informations in the list
			    push!(components[key], (WeakRef(entity),c))
			else

				# We create a new set of data
				components[key] = ComponentData(UInt[], StructArray{typeof(c)}(undef, 0))

				# And we add our data
				push!(components[key], (WeakRef(entity), c))
				entity.world_pos[key] = 1 # Since the entity is the first one in the list
			end
		end
		
		for archetype in keys(ecs.groups)
			if _match_archetype(entity, archetype)
				group::aSoA = ecs.groups[archetype]

				push!(group, entity.world_pos)

				# We save the entity's index to delete it more easily with a simple swap deletion
				entity.positions[archetype] = length(group.data[2])-1
			end
		end
	end

	return nothing
end

"""
    remove_entity!(ecs::ECSManager{T}, entity::T) where T <: AbstractEntity

This remove an entity to the ECS and remove it in the existing archetype where he is.
"""
function remove_entity!(ecs::ECSManager{A}, entity::Entity{A}) where A <: AbstractArchetype
	_remove_in_world!(ecs,entity)
	for archetype in keys(ecs.groups)
		if _match_archetype(entity,archetype)

			## We use a swap deletion to avoid reindexing the whole array
			group::aSoA = ecs.groups[archetype]
			idx = entity.positions[archetype]
			tmp = _swap_remove!(group, idx)
			
			if !isnothing(tmp)
				obj = ecs.components[keys(group.data)[1]][1][tmp[1]].value
				obj.positions[archetype] = idx
		    end
		end
	end

	return nothing
end

"""
    attach_component!(ecs::ECSManager, entity::Entity, component::AbstractComponent)

Use this function to add a new component to an entity
"""
function attach_component!(ecs::ECSManager, entity::Entity, component::AbstractComponent)
	
	# First of all, we replace the old component to put a new one containint the new component
	key = get_name(component)
	name= Namedtuple{(key,)}((component,))
    entity.components[key] = merge(entity.components, name)

    # If the entity is already registered in the ECS manager
	if haskey(ecs.entities,entity.id)

		for archetype in keys(ecs.groups)
			if _match_archetype(entity,archetype) && _match_archetype(archetype, component)
				push!(ecs.groups[archetype], entity)
			end
		end
		
	end
end

"""
    detach_component!(ecs::ECSManager, entity::Entity, component::AbstractComponent)

Use this function to remove a new component to an entity
"""
function detach_component!(ecs::ECSManager{A}, entity::Entity{A}, component::AbstractComponent)  where A <: AbstractArchetype
	if haskey(ecs.entities, entity.id)
		for archetype in ecs.groups
			if _match_archetype(entity,archetype) && _match_archetype(archetype, component)

				## We use a swap deletion to avoid reindexing the whole array
				group::aSoA = ecs.groups[archetype]
				tmp = pop!(group)
				group[entity.position[archetype]] = tmp
			end
		end
	end

	name = get_name(component)
	entity.components = _delete_tuple(entity.components, name)
end

function subscribe!(ecs::ECSManager{A}, system::AbstractSystem, components::Tuple) where A <: AbstractArchetype
	
	# If the is not system with a subscription to the given archetype
	archetype = A(components)
	if !haskey(ecs.groups, archetype)
		names = get_name.(components)
		system.archetype = archetype
		ecs.systems[archetype] = AbstractSystem[system]
		ecs.groups[archetype] = aSoA{NTuple{length(names), Int}}(names)
		for entity in values(ecs.entities)
			if _match_archetype(entity, archetype)
				push!(ecs.groups[archetype], entity.components)
			end
		end
	else
		push!(ecs.systems[archetype], system)
	end

	return nothing
end

"""
    dispatch_data(ecs)

This function will distribute data to the systems given the archetype they have subscribed for.
"""
function dispatch_data(ecs::ECSManager)
	for archetype in keys(ecs.systems)
		data = ecs.groups[archetype]
		systems = ecs.systems[archetype]

		for system in systems
		    put!(system.flow, (WeakRef(ecs.components),WeakRef(data)))
		end
	end
end


run!(sys::T, batch) where T <: AbstractSystem = error("run! is not defined for the system of type $T")

function run_system!(@nospecialize(system::AbstractSystem))

	# We skip the error checking on purpose
	# Just taking data, extremely low risk of error
	errormonitor(
		@async while system.active
			batch = take!(system.flow)
			result = run!(system, batch)

			children = system.children
			
			if result != nothing
				feed_children(system, result)
			end
		
		end
	)
end

function feed_children(@nospecialize(sys::AbstractSystem), data)
	children = sys.children
		
	for child in children
		put!(child.flow, data)
	end
	
end

"""
    listen_to(source::AbstractSystem, listener::AbstractSystem)

This function make the system `listener` wait for data coming from the system `source`
"""
@inline Base.@nospecializeinfer function listen_to(@nospecialize(source::AbstractSystem), @nospecialize(listener::AbstractSystem))

	## We will skip error checking on purpose
	# We are just fetching data so there should be not problem
	# We will just async this to ensure that we are still on the main thread
    push!(source.children, listener)
end

"""
    listen_to(ecs::ECSManager, archetype::NTuple{N,Symbol}, listener::AbstractSystem, num=1) where N

This function will make the system `listener` wait for data coming the `num` systems who have request the components `archetype`
"""
function listen_to(ecs::ECSManager{A}, components::Tuple, listener::AbstractSystem, num=1) where A <: AbstractArchetype
	archetype = A(components)
	if haskey(ecs.systems, archetype)
		source = ecs.systems[archetype]

		(num == -1) && (num = length(source))
		for i = 1:num
		    listen_to(source[i], listener)
		end
	else
		@warn "There is no system matching the archetype $archetype yet."
	end
end

function _swap_remove!(A, i::Int)
	tmp = pop!(A)
	if i <= length(A)
		A[i] = tmp
		return tmp
	end
end

function _remove_in_group!(group, entity, archetype)
	idx = entity.positions[archetype]
	tmp = _swap_remove!(group,idx)
	tmp.positions[archetype] = idx
end

function _remove_in_world!(ecs, entity)
	for key in keys(entity.components)

		# We get the position of the entity in the world
		i = entity.world_pos[key]
		data = ecs.components[key]
		
		# We remove it
		
		id, d = pop!(data)
		
		data[1][i], data[2][i] = id, d

		obj = id.value

		# Then set the new object at his position
		obj.world_pos[key] = i
    end
    delete!(ecs.entities, entity.id)
end