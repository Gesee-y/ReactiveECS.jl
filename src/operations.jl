#########################################################################################################################
###################################################### OPERATIONS #######################################################
#########################################################################################################################

######################################################## Export #########################################################

export create_entity, request_entity

######################################################### Core ##########################################################

"""
    create_entity(ecs::ECSManager, comp::NamedTuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)

This will create a new entity in the manager `ecs`, with the components `comp` and with the given `parent`.
If this entity is the first one with this set of argument, a new partition with the given `size` will be created

    create_entity(ecs::ECSManager, key::Tuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)

This will create entity with the given signature but with uninitialized components.
`key` is a tuple of symbols, where each symbol is a component.
"""
function create_entity(ecs::ECSManager, comp::NamedTuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)
	table = ecs.table
	key = keys(comp)
	partitions = table.partitions

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	!haskey(partitions, signature) && createpartition(table, signature, size)
	id = addtopartition(table, signature) # We add the entity to the correct partition

	entity = Entity(id, signature, key, WeakRef(ecs), get_id(parent), UInt[])
	setrow!(table, id, comp) # We then initialize the components

	table.entities[id] = entity

	return entity
end
function create_entity(ecs::ECSManager, key::Tuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)
	table = ecs.table
	key = to_symbol.(key)
	partitions = table.partitions

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	!haskey(partitions, signature) && createpartition(table, signature, size)
	id = addtopartition(table, signature) # We add the entity to the correct partition

	entity = Entity(id, signature, key, WeakRef(ecs), get_id(parent), UInt[])
	table.entities[id] = entity

	return entity
end

function request_entity(ecs::ECSManager, comp::NamedTuple, count::Int; parent=ecs)
	table = ecs.table
	key = keys(comp)
	partitions = table.partitions
    s = table.entity_count+1
    e = table.entity_count+count
    parent_id = get_id(parent)
    ref = WeakRef(ecs)
    entities = Vector{Entity}(undef, count)

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	allocate_entity(table, count, signature)
    
    @threads for i in s:e
    	setrow!(table, i, comp)
    end

    r = EntityRange(s,e,0,ref,key,parent_id,signature)
    #append!(table.entities, entities)

	return r
end
function request_entity(ecs::ECSManager, key::Tuple, count::Int; parent=ecs)
	table = ecs.table
	partitions = table.partitions
    s = table.entity_count+1
    e = table.entity_count+count
    parent_id = get_id(parent)
    ref = WeakRef(ecs)

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	allocate_entity(table, count, signature)
    
    r = EntityRange(s,e,0,ref,key,parent_id,signature)
    #@inbounds for i in s:e
    #	entities[i-s+1] = Entity(i, signature, key, ref, parent_id, UInt[])
    #end

	return r
end