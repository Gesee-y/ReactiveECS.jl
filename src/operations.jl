##################################################################################################################
#################################################   OPERATIONS   #################################################
##################################################################################################################

export create_entity!, remove_entity!
export attach_component!, detach_component!

"""
    create_entity(ecs::ECSManager; components...)

This function create a new entity with the given components.
`components` keys should match the `get_name` of the component.
"""
function create_entity!(ecs::ECSManager; kwargs...)
	components = NamedTuple(kwargs)
	value = values(components)
	signature = get_bits(value)
	entity_components = NamedTuple{keys(components)}(typeof.(value))
	id = get_free_indice(ecs)

	entity = Entity(id, ecs, entity_components)
	
	push!(ecs, entity, components)
	_add_to_archetype(ecs.archetypes, entity, signature)

	return entity
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
				if !in(entity.positions[archetype], arch_data)
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
function detach_component!(entity::Entity; component)
	name = get_name(component)
	T = typeof(components)

	# We first check if the component is there
    !(name in keys(entity.components)) && return

	# We fused the entity existing component with the new one
	i = findfirst(keys(entity.components), name)

	# We make the new component list
	ky = (keys(entity.components)[begin:i-1]..., keys(entity.components)[i+1:end]...)
	vl = (values(entity.components)[begin:i-1]..., values(entity.components)[i+1:end]...)
	entity.components = NamedTuple{ky}(vl)

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
				if haskey(entity.positions, archetype)
					tmp = pop!(arch_data)
					arch_data[id] = tmp
				end
			end
		end
	end

	return nothing
end

##################################################### Helpers #####################################################

function _add_to_archetype(data::Dict{BitType, ArchetypeData}, entity::Entity, signature::BitType)
	for archetype in keys(data)
		
		# Checking the signature
		if match_archetype(signature, archetype)
			arch_data = get_data(data[archetype])
			push!(arch_data, get_id(entity)) # We add entity index in the archetype group
			entity.positions[archetype] = length(arch_data) # We set the entity's position in the archetype
		end
	end
end

function _remove_from_archetype(data::Dict{BitType, ArchetypeData}, entity::Entity)
	for archetype in keys(entity.positions)
		arch_data = get_data(data[archetype])
		tmp = pop!(arch_data) # We get the last index
		arch_data[entity.positions[archetype]] = tmp	
	end
end