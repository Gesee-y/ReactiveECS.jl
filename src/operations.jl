##################################################################################################################
#################################################   OPERATIONS   #################################################
##################################################################################################################

export create_entity!, remove_entity!, queue_add!, request_entity
export attach_component!, detach_component!

"""
    create_entity(ecs::ECSManager; components...)

This function create a new entity with the given components.
`components` keys should match the `get_name` of the component.
"""
function create_entity!(ecs::ECSManager, components::NamedTuple)

	# Creating relevant variable
	value = values(components)
	signature = get_bits(value) # The entity's signature
	entity_components = typeof.(value) # tuple of components types
	id = get_free_indice(ecs) # The entity's id is fetched in the available id of the manager

    entity = Entity(id, ecs, entity_components)
	
	push!(ecs, entity, components)
	_add_to_archetype(ecs.archetypes, entity, signature)
    
	return entity
end
function create_entity!(ecs::ECSManager, signature::Tuple, archetype=0)

	id = get_free_indice(ecs) # The entity's id is fetched in the available id of the manager
    entity = Entity(id, ecs, signature)
    w = ecs.world_data
    push!(ecs.entities, entity)
    resize!(w, length(w)+1)
	
	_add_to_archetype(ecs.archetypes, entity, archetype)
    
	return entity
end
create_entity!(ecs::ECSManager; kwargs...) = create_entity!(ecs, NamedTuple(kwargs))

Base.@propagate_inbounds function request_entity(ecs::ECSManager, num::Int, signature::Tuple)
    entities = Entity[]
    world = ecs.world_data
    
    st = length(entities)
    en = st + num
    arch = get_bits(signature)

    matched = Vector{ArchetypeData}()
    archetypes = ecs.archetypes
    sizehint!(matched, length(archetypes))
    sizehint!(entities, en)
    resize!(world, en)
    
    for archetype in keys(archetypes)
    	if match_archetype(arch, archetype)
    		push!(matched, archetypes[archetype])
    	end
    end

    @inbounds for i in st:en
        entity = Entity(i, ecs, signature)
        for archetype in matched
        	archetype.positions[i] = length(get_data(archetype))+i
        end
    	entities[i] = entity
    end

    for archetype in matched
		arch_data = get_data(archetype)
		append!(arch_data, st:en)
    end

    append!(ecs.entities, entities)

    return entities
end

"""
    queue_add!(ecs::ECSManager, components::NamedTuple)

Use this function to add entity to a queue, to be added later (more precisely at dispatch time)
"""
function queue_add!(ecs::ECSManager, components::NamedTuple)
	value = values(components)
	id = get_free_indice(ecs) # The entity's id is fetched in the available id of the manager

    entity = Entity(id, ecs, typeof.(value))
    add_to_addqueue(ecs, entity, components)
end
queue_add!(ecs::ECSManager; kwargs...) = queue_add!(ecs, NamedTuple(kwargs))

function add_queued(ecs::ECSManager)
	merged = append!(ecs, ecs.queue.add_queue_in, ecs.queue.add_queue_out, ecs.queue.data)
    for entity in merged
    	signature = get_bits(entity.components)
    	_add_to_archetype(entity.archetypes, entity, signature)
    end

    empty!(ecs.queue.add_queue)
    empty!(ecs.queue.data)
end

"""
    remove_entity!(ecs::ECSManager, entity::Entity)

This function remove the entity from the `ecs` or the world
"""
function remove_entity!(ecs::ECSManager, entity::Entity)
	add_to_free_indices(ecs, entity.id)
	_remove_from_archetype(ecs.archetypes, entity)
end

"""
    queue_deletion!(ecs::ECSManager, entity::Entity)

Use this function to put entity to a queue, to be deleted later (more precisely at dispatch time)
"""
queue_deletion(ecs::ECSManager, entity::Entity) = add_to_delqueue(ecs, entity)

function delete_queued(ecs::ECSManager)
	queue = ecs.queue.deletion_queue
	for i in eachindex(queue)
		remove_entity!(ecs, queue[i])
	end

	empty!(queue)
end

"""
    attach_component!(entity::Entity; component)

Use this function to add a new component to an existing entity.
Make sure the entity has already been added to the world.
"""
function attach_component!(entity::Entity; component)
	name = get_name(component)
	T = typeof(components)

	# We first check the entity is not already there
    name in keys(entity.components) && return

	# We fused the entity existing component with the new one
	entity.components = merge(entity.components, NamedTuple{(name,)}((T,)))
	signature = get_bits(values(entity.components)) # And the store the new signature of the entity
	ecs = entity.world.value # We get the ECSManager

	if ecs != nothing # Nothing means the entity have been created in inconventional way
		data = ecs.world_data.data # We get our relevant data
		id = get_id(entity)
		archetypes = ecs.archetypes
		
		# Checking if the component already exist and creating a section for it if not
		haskey(data, name) || (data[name] = StructArray{T}(undef, length(data)))
		data[name][id] = components

		# Here we add the entity to all the signature he now match
		for archetype in keys(archetypes)

			# If the entity match the signatur but isn't int the archetype
			# We add it
			if match_archetype(signature, archetype)
				arch_data = get_data(archetypes[archetype])
				positions = archetypes[archetype].positions
				if !in(id, keys(positions))
					push!(arch_data, id)
				end
			end
		end
	end

	return nothing
end

"""
    detach_component!(entity::Entity; component)

Use this function to remove a component from an existing entity.
Make sure the entity has already been added to the world.
"""
Base.@propagate_inbounds function detach_component!(entity::Entity; component)
	name = get_name(component)
	T = typeof(components)

	# We first check if the component is there
    !(name in keys(entity.components)) && return

	# We fused the entity existing component with the new one
	i = findfirst(keys(entity.components), name)

	# We make the new component list
	vl = (entity.components[begin:i-1]..., entity.components[i+1:end]...)
	entity.components = vl

	signature = get_bits(vl) # And the store the new signature of the entity
	ecs = entity.world.value # We get the ECSManager

	if ecs != nothing # Nothing means the entity have been created in inconventional way
		data = ecs.world_data.data # We get our relevant data
		id = get_id(entity)
		archetypes = ecs.archetypes

		# Here we add the entity to all the signature he now match
		for archetype in keys(archetypes)

			# If the entity doesn't match the signature but yet the entity possess it
			# We remove it
			if !match_archetype(signature, archetype)
				arch_data = get_data(archetypes[archetype])
				positions = archetypes[archetype].positions
				if haskey(id, keys(positions))
					tmp = pop!(arch_data)
					arch_data[id] = tmp
				end
			end
		end
	end

	return nothing
end

##################################################### Helpers #####################################################

Base.@propagate_inbounds function _add_to_archetype(data::Dict{BitType, ArchetypeData}, entity::Entity, signature::BitType)
	for archetype in keys(data)
		
		# Checking the signature
		if match_archetype(signature, archetype)
			archetype_data::ArchetypeData = data[archetype]
			positions::Dict{Int,Int} = archetype_data.positions
			entity_id::Int = get_id(entity)
			arch_data::Vector{Int} = get_data(archetype_data)
			push!(arch_data, get_id(entity)) # We add entity index in the archetype group
			
			positions[entity_id] = length(arch_data) # We set the entity's position in the archetype
		end
	end
end

Base.@propagate_inbounds function _remove_from_archetype(data::Dict{BitType, ArchetypeData}, entity::Entity)
	for archetype in keys(entity.positions)
		archetype_data = data[archetypes]
		pos::Int = archetype_data.positions[get_id(entity)]
		positions = archetype_data.positions
		arch_data::Vector{Int} = get_data(archetype_data)
		if pos > 0 && !isempty(arch_data)
			tmp::Int = pop!(arch_data) # We get the last index
			(!isempty(arch_data) && pos <= length(arch_data)) && (arch_data[pos] = tmp)
		else
			delete!(entity.positions, archetype)
		end
	end
end
