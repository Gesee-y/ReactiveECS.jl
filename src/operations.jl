#########################################################################################################################
###################################################### OPERATIONS #######################################################
#########################################################################################################################

######################################################## Export #########################################################

export create_entity!, request_entity!, frequest_entity!, remove_entity!, attach_component, detach_component

######################################################### Core ##########################################################

"""
    create_entity!(ecs::ECSManager, comp::NamedTuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)

This will create a new entity in the manager `ecs`, with the components `comp` and with the given `parent`.
If this entity is the first one with this set of argument, a new partition with the given `size` will be created

    create_entity!(ecs::ECSManager, key::Tuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)

This will create entity with the given signature but with uninitialized components.
`key` is a tuple of symbols, where each symbol is a component.
"""
function create_entity!(ecs::ECSManager, comp::NamedTuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)
	table = get_table(ecs)
	key = keys(comp)
	partitions = table.partitions

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	createpartition(table, signature, size)
	id = addtopartition(table, signature) # We add the entity to the correct partition

	entity = Entity(id, signature, WeakRef(ecs))
	setrow!(table, id, comp) # We then initialize the components

	table.entities[id] = entity

	return entity
end
function create_entity!(ecs::ECSManager, key::Tuple; parent=ecs, size=DEFAULT_PARTITION_SIZE)
	table = get_table(ecs)
	key = to_symbol.(key)
	partitions = table.partitions

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	createpartition(table, signature, size)
	id = addtopartition(table, signature) # We add the entity to the correct partition

	entity = Entity(id, signature, WeakRef(ecs))
	table.entities[id] = entity

	return entity
end
create_entity!(ecs::ECSManager; kwargs...) = create_entity!(ecs, NamedTuple(kwargs))

"""
    request_entity!(ecs::ECSManager, comp::NamedTuple, count::Int; parent=ecs)

This function create `count` number of entity with the given components in `comp` and return an `EntityRange`.
Note that this function doesn't hysically make the entities. They are there and can be processed.
But you will have to use `get_entity` on that range.

    request_entity!(ecs::ECSManager, key::Tuple, count::Int; parent=ecs)

Do the same as above but doesn't initialize the components so they just have garbage value.
Note that this is significantly faster than the other version of this function.
"""
function request_entity!(ecs::ECSManager, comp::NamedTuple, count::Int; parent=ecs)
	table = get_table(ecs)
	key = keys(comp)
	partitions = table.partitions
    parent_id = get_id(parent)
    ref = WeakRef(ecs)

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	ranges = allocate_entity(table, count, signature)
    
    for r in ranges
    	setrowrange!(table, r, comp)
    end

    #r = EntityRange(s,e,0,ref,key,parent_id,signature)
	#return r
end
function frequest_entity!(ecs::ECSManager, comp::NamedTuple, count::Int; parent=ecs)
	table = get_table(ecs)
	key = keys(comp)
	partitions = table.partitions
    parent_id = get_id(parent)
    ref = WeakRef(ecs)

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	ranges = allocate_entity(table, count, signature)
    
    for r in ranges
    	fsetrowrange!(table, r, comp)
    end

    #r = EntityRange(s,e,0,ref,key,parent_id,signature)
	#return r
end
function request_entity!(ecs::ECSManager, key::Tuple, count::Int; parent=ecs)
	table = get_table(ecs)
	partitions = table.partitions
    s = table.row_count+1
    e = table.row_count+count
    parent_id = get_id(parent)
    ref = WeakRef(ecs)

    # We get the bit representation of that set of components
	signature = get_bits(table, key)
	allocate_entity(table, count, signature)
    
    r = EntityRange(s,e,0,ref,key,parent_id,signature)
	return r
end

"""
    remove_entity!(ecs::ECSManager, e::Entity)

This remove an entity from the world.
"""
function remove_entity!(ecs::ECSManager, e::Entity)
	table = get_table(ecs)
	override_remove!(table, e)
	e.world = WeakRef()
end

"""

"""
function attach_component(ecs::ECSManager, e::Entity, c::AbstractComponent)
	symb = to_symbol(c)
	bit::UInt128 = one(UInt128) << ecs.components_ids[symb]
	if iszero(e.archetype & bit)
		table = get_table(ecs)
		old_signature = e.archetype
		signature = old_signature | bit
		change_archetype!(table, e, old_signature, signature)
		table.columns[symb][get_id(e)[]] = c
		e.archetype = signature
	end
end
function attach_component(ecs::ECSManager, e::Entity, c::AbstractComponent...)
	symb = to_symbol.(c)
	table = get_table(ecs)
	bit::UInt128 = get_bits(table,symb)
	if (e.archetype & bit < bit)
		old_signature = e.archetype
		signature = old_signature | bit
		change_archetype!(table, e, old_signature, signature)
		
		i = get_id(e)[]
		columns = table.columns
		@inbounds for j in eachindex(symb)
		    columns[symb[j]][i] = c[j]
		end
		e.archetype = signature
	end
end
function attach_component(ecs::ECSManager, ents::Vector{Entity}, c::AbstractComponent)
	isempty(ents) && return
	
	e = ents[1]
	symb = to_symbol(c)
	bit::UInt128 = one(UInt128) << ecs.components_ids[symb]
	if iszero(e.archetype & bit)
		table = get_table(ecs)
		old_signature = e.archetype
		signature = old_signature | bit
		change_archetype!(table, ents, old_signature, signature)
		col = table.columns[symb] 

		setrowrange!(col, get_id.(ents), c)
	end
end
function attach_component(ecs::ECSManager, ents::Vector{Entity}, c::AbstractComponent...)
	isempty(ents) && return
	
	e = ents[1]
	symb = to_symbol.(c)
	table = get_table(ecs)
	old_signature = e.archetype
	bit::UInt128 = get_bits(table, symb)
	if old_signature & bit < bit
		signature = old_signature | bit
		change_archetype!(table, ents, old_signature, signature, false)
		
		fix = Base.Fix1(getindex, table.columns)
		columns = fix.(symb)
		setrowrange!(get_id.(ents), columns, c, Val(length(symb)))
	end
end

function detach_component(ecs::ECSManager, e::Entity, symb::Symbol)
	bit::UInt128 = one(UInt128) << ecs.components_ids[symb]
	if (e.archetype & bit == bit)
		old_signature = e.archetype
		signature = old_signature & ~bit
		change_archetype!(get_table(ecs), e, old_signature, signature)
		e.archetype = signature
	end
end
function detach_component(ecs::ECSManager, e::Entity, symb...)
	table = get_table(ecs)
	bit::UInt128 = get_bits(table, symb)
	if (e.archetype & bit > 0)
		old_signature = e.archetype
		signature = old_signature & ~bit
		change_archetype!(table, e, old_signature, signature)
		e.archetype = signature
	end
end
function detach_component(ecs::ECSManager, ents::Vector{Entity}, symb::Symbol)
	isempty(ents) && return
	
	e = ents[1]
	bit::UInt128 = one(UInt128) << ecs.components_ids[symb]
	if (e.archetype & bit == bit)
		old_signature = e.archetype
		signature = xor(old_signature, bit)
		change_archetype!(get_table(ecs), ents, old_signature, signature)
	end
end
function detach_component(ecs::ECSManager, ents::Vector{Entity}, symb...)
	isempty(ents) && return
	
	e = ents[1]
	table = get_table(ecs)
	bit::UInt128 = get_bits(table, symb)
	if (e.archetype & bit >= 0)
		old_signature = e.archetype
		signature = xor(old_signature, bit)
		change_archetype!(table, ents, old_signature, signature)
	end
end