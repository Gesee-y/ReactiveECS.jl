#########################################################################################################################
####################################################### TABLE ###########################################################
#########################################################################################################################
using BenchmarkTools

####################################################### Export ##########################################################

export ArchTable, TableColumn, TableRange, TablePartition
export swap!, swap_remove!, get_entity, get_range, getdata

######################################################## Core ###########################################################

const DEFAULT_PARTITION_SIZE = 2^12

"""
    mutable struct EntityRange
		const s::Int
		const e::Int
		init::Int
		world::WeakRef
		const key::Tuple
		const signature::UInt128

A range of identical entities.
This is used for lazy initializations. Instead of initializing every entities right away, we can just represent them
like this.
`s` is the starting point of the range of entities
`e` is the end of the range
`init` is how many entities have already been inited
`key` the set of components of the entities in the range
`signature` is the archetype of these entities
"""
mutable struct EntityRange
	const s::Int
	const e::Int
	init::Int
	world::WeakRef
	const key::Tuple
	const parent_id::Int
	const signature::UInt128
end

"""
    struct TableColumn{T}
    	id::Int
    	data::StructArray{T}
    	locks::HierarchicalLock{T}

This represent a column of the table. A column is in a fact a Struct of array where each field is a vector where each
index is an entity.
`id` is the position of the bit representing this column.
"""
struct TableColumn{T,N,C,I}
	id::Int
    data::StructArray{T,N,C,I}
    locks::HierarchicalLock{T}

    ## Constructor
    TableColumn(id::Int, s::StructArray{T,N,C,I}) where {T,N,C,I} = new{T,N,C,I}(id,s, HierarchicalLock{T}())
    TableColumn{T}(id::Int,::UndefInitializer, n::Integer) where T = TableColumn(id,StructArray{T}(undef, n))
end

"""
    mutable struct TableRange
		s::Int
		e::Int
		size::Int64

This is used to represent a range for a partition.
It allow more granular control for each range (instead of having a fixed size for every range).
"""
mutable struct TableRange
	s::Int
	e::Int
	size::Int64
end

"""
    mutable struct TablePartition
		zones::Vector{TableRange}
		to_fill::Vector{Int}

This represent a partiton. Partition are set of ranges for entities with the same set of components.
This allows fast and localized entities processing.
`zones` is the set of range corresponding to that partition.
`to_fill` is the indices of the range needing to be filled.		
"""
mutable struct TablePartition
	zones::Vector{TableRange}
	to_fill::Vector{Int}
end

"""
    mutable struct ArchTable{T} where T <: Integer
		columns::Dict{Type, TableColumn}
		partitions::Dict{T, UnitRange{Int64}}

Represent a Table. `T` is the actual type used to represent an archetypes.
`columns` is a dict where each type map a component.
`partitions` is a Dict where each archetype map a compact field of components with that archetype.
"""
mutable struct ArchTable{T}
	entities::Vector{Optional{Entity}}
	columns::Dict{Symbol, TableColumn}
	partitions::Dict{T, TablePartition}
	entity_count::Int
	component_count::Int
	row_count::Int

	## Constructors

	ArchTable{T}() where T = new{T}(Optional{Entity}[], Dict{Symbol, TableColumn}(), Dict{T, TablePartition}(), 0, 0, 0)
end

##################################################### Functions #########################################################

Base.eachindex(v::TableColumn) = eachindex(getdata(v))
Base.getindex(v::TableColumn, i) = getdata(v)[i]
Base.setindex!(v::TableColumn, val, i) = (getdata(v)[i] = val)
getdata(v::TableColumn) = getfield(v, :data)
getlocks(v::TableColumn) = getfield(v, :locks)
get_lock(v::TableColumn, path::NTuple{N,Symbol}) where N = HierarchicalLocks.get_node(getlocks(v).root, path)
get_id(t::TableColumn) = getfield(t, :id)
Base.getproperty(v::TableColumn, s::Symbol) = get_field(v, Val(s))

"""
    register_component!(table::ArchTable, T::Type)

This register a component in a table, assigning to him a bit position.
This also initialize the column for this component. Should be done after defining the component.
"""
function register_component!(table::ArchTable, T::Type)
	columns = table.columns
	key = to_symbol(T)
	count = length(table.entities)
	!haskey(columns, key) && (table.component_count+=1; 
		columns[key] = TableColumn{T}(table.component_count, undef, count))
end

"""
    initcolumns!(t::ArchTable, data::NamedTuple)

This initialize the columns for the components contained in `data`.
"""
function initcolumns!(t::ArchTable, data::NamedTuple)
	columns = t.columns
	count = t.row_count+1
	for d in data
		key = to_symbol(d)
		!haskey(columns, key) && (t.component_count+=1; 
			columns[key] = TableColumn{typeof(data[key])}(t.component_count, undef, count))
	end
end

"""
    addrow!(t::ArchTable, data::NamedTuple)

Create a new row from the given `data` by resizing it and adding a row.
Data added that way won't belong to any partition and we will never be iterated in a system.
This function is not advised, at least you know what you are doing.
"""
function addrow!(t::ArchTable, data::NamedTuple)
	columns = t.columns
	count = t.row_count
	resize!(t, count)
	for key in keys(data)
		elt = data[key]
		columns[key][count] = data[key]
    end
end

"""
    setrow!(t::ArchTable, i::Int, data)

This set the components at index `i` in the table `t` with the given `data`.
Useful for inplace modifications of an entity.
`data` can be a `NamedTuple`, a `Dict` or an `AbstractComponent`.
"""
function setrow!(t::ArchTable, i::Int, data)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = keys(data)
	vals = values(data)
	@inbounds for j in eachindex(key)
	    k = key[j]
	    getfield(columns[k],:data)[i] = vals[j]
	end
end
function setrow!(t::ArchTable, i::Int, c::AbstractComponent)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = to_symbol(c)
	@inbounds getfield(columns[key],:data)[i] = c
end

"""
    setrowrange!(t::ArchTable, r::UnitRange{Int}, data)

This set a given range of a table with the given `data` which is a dictionnary or a named tuple.
"""
function setrowrange!(t::ArchTable, r::UnitRange{Int}, data)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = keys(data)
	vals = values(data)
	@inbounds for j in eachindex(key)
	    k = key[j]
	    v = vals[j]
	    vec = getfield(columns[k],:data)
	    @threads for i in r
	    	vec[i] = v
	    end
	end
end

"""
    allocate_entity(t::ArchTable, n::Int, archetype::Integer; offset=2048)

This will allocate `n` entities in the table `t`. More precisely for the partition of the given `archetype`
`offset` is how many entities will be allocated in case the allocation left half-filled ranges.
This function return a set of interval corresponding to the indices of entities allocated.
"""
function allocate_entity(t::ArchTable, n::Int, archetype::Integer; offset=2048)
	partitions = t.partitions
	intervals = UnitRange{Int64}[]

	# If the partition fot that archetype doesn't yet exist
	if !haskey(partitions, archetype)
		# Just creating a new partition
		partition = TablePartition(TableRange[TableRange(t.row_count+1,t.row_count+n, n)], Int[])
    	partitions[archetype] = partition # And creating that new archetype

        push!(intervals, t.row_count+1:t.row_count+n)
        resize!(t, length(t.entities)+n+1)
        t.entity_count += n
    	
        return intervals
    end
    
	partition = partitions[archetype]
	zones = partition.zones
	part_to_fill = partition.to_fill
    m = n # Entity left to be added

	count = length(part_to_fill)

    # While there are still entities to add and there are still ranges to fill
	while m > 0 && count > 0
		i = part_to_fill[count] # We get the indice of the zone to fill
		zone = zones[i]
		size = zone.size

		# The number of entities needed to fill this
		to_fill = size - length(zone) 
		v = clamp(m,0,to_fill)

		# If there are more entities to add than space available, then that zone is filled
		m >= to_fill && pop!(part_to_fill)

        # We then add to interval our newly filled zone
		push!(intervals, zone[end]:(zone[end]+v))
		zone.e += v

		m -= to_fill
		count -= 1
	end

    # If after all that there is still some entities to add
	if m > 0
		# We create a new range for it with the given offset
		push!(zones, TableRange(t.row_count+1, t.row_count+m+offset, m+offset))
		push!(part_to_fill, length(zones)) # We add this new zone as to be filled
	    
	    nsize = length(t.entities)+m+offset
		resize!(t, nsize) # Finally we just resize our table
	end

	t.entity_count += n

    return intervals
end

"""
    createpartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)

Create a new partition with no entity.
This only has effect if `archetype` doesn't yet exist in the table `t`
"""
function createpartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)
	partitions = t.partitions
	if !haskey(partitions, archetype)
		# We initialize our partition with the range and we immediately set that range as to be filled
		partition = TablePartition(TableRange[TableRange(t.row_count+1,t.row_count, size)], Int[1])
    	partitions[archetype] = partition

    	resize!(t, t.row_count+size)
    end
end

"""
    addtopartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)

This add a new slot to a partition or create another range if necessary and return the newly created id.
This will panic if there is no partitions matching that archetype
"""
function addtopartition(t::ArchTable{T}, archetype::Integer, size=DEFAULT_PARTITION_SIZE) where T
	partitions = t.partitions
    partition = partitions[archetype]
    
    zones::Vector{TableRange} = partition.zones
    zone = zones[end]
    to_fill::Vector{Int} = partition.to_fill
    id = t.entity_count+1


    # if there is some zone to fill
    if !isempty(to_fill)
    	fill_id = to_fill[end]
    	zone = zones[fill_id]
    	zone.e += 1
    	id = zone[end]
        
        # if we fulfilled a zone, we remove it from the zone to fill
    	id >= size && pop!(to_fill)
    else
    	# We create a new range and add it to the one to be filled
    	zone[end] == t.entity_count
    	push!(zones, TableRange(id,id,size))
    	push!(to_fill, length(zones))
    	resize!(t, id+size-1)
    end
    
    t.entity_count += 1
    
    return id
end

get_column(t::ArchTable, field::Symbol) = t.columns[field]

function Base.resize!(t::ArchTable, n::Int)
    columns = t.columns
    resize!(t.entities, n)
    t.row_count = n
    for column in values(columns)
        resize!(getdata(column), n)
    end	
end

"""
    swap_remove!(t::ArchTable, e::Entity)

This will swap the entity `e` with the last valid entity then substract 1 to the entities count.
"""
function swap_remove!(t::ArchTable, e::Entity)
	partition = t.partitions[e.archetype]
	to_fill = partition.to_fill 
	entities = t.entities
	zones = partition.zones

	i = get_id(e)[]
    
    # If there are some zone to fill
	if !isempty(to_fill)
		fill_id = to_fill[end]

		j = zones[fill_id][end]

        # If the last index is the same as i then we can just shrink the zone
		if i == j
			zones[fill_id].e -= 1
		    entities[i] = nothing
		else
			# We check this in case the entity is undefined du to some resizing
			if !isdefined(entities, j)
				entities[i] = Entity(i, e.archetype, e.components, e.world, -1, Int[])
				entities[j] = nothing
		    else
			    entities[j], entities[i] = nothing, entities[j]
			    e.ID[], entities[i].ID[] = j, i
			
			    swap!(t, i, j; fields=e.components)
		    end
		end

        # If the zone is filled
		if length(zones[fill_id]) < 1
			pop!(zones)
			pop!(to_fill)
		end
	else
		partition.zones[end].s -= 1
		entities[i] = nothing
		push(to_fill, length(partition.zones))
	end

    t.entity_count -= 1

	for ids in e.children
		child = entities[ids[]]
		swap_remove!(child)
	end
end

"""
    swap!(t::ArchTable, i::Int, j::Int; fields=())

Swap the component given by `fields` of the rows `i` and `j`.
This doesn't modify the entity, it just swap their component.

    swap!(t::ArchTable, e1::Entity, e2::Entity)

Does the same as above but instead, `fields` is the components of `e1`.
`i` and `j` are respectively the index of `e1` and `e2` whose index will be swapped at the end.

    swap!(arch::TableColumn, i::Int, j::Int)

This will swap the data of the index `i` and `j` of the column `arch`.
"""
function swap!(t::ArchTable, i::Int, j::Int; fields=())
    for f in fields
    	arch = t.columns[f]
    	swap!(arch, i, j)
    end
end
function swap!(t::ArchTable, e1::Entity, e2::Entity)
	i, j = get_id(e1)[], get_id(e2)[]
	swap!(t, i, j, fields=e1.components)
	e1.ID[], e2.ID[] = j, i
end
@generated function swap!(arch::TableColumn{T}, i::Int, j::Int) where T
    fields=fieldnames(T)
    expr = Expr(:block)
    swaps = expr.args
    for f in fields
    	type = fieldtype(T, f)
    	data = gensym()
        push!(swaps, quote 
        	$data::Vector{$type} = arch.$f
        	$data[i],  $data[j] =  $data[j],  $data[i]
        end)
    end

    return expr
end

"""
    change_archetype(t::ArchTable, e::Entity, archetype::Integer)

Move the entity `e` of the table `t` from his archetype to a new `archetype`.
This function assume `t` contain a partition for `archetype` else it will panic.
"""
function change_archetype(t::ArchTable, e::Entity, archetype::Integer; fields=e.components)

	# Relevant data neatly organized
	if !haskey(t.partitions, archetype)
		createpartition(t, archetype)
	end
    new_partition = t.partitions[archetype]
	partition = t.partitions[e.archetype]
    new_to_fill = new_partition.to_fill
	new_zones = new_partition.zones 
    to_fill = partition.to_fill
	zones = partition.zones
    entities = t.entities
	zone = zones[end]
	j = zone[end]
	i = get_id(e)[]

    # We first something like a deletion to the entity
    # Taking it to the last position and shrinking the range
    
    swap!(t,i,j,fields=fields)
	zone.e -= 1
	
	# Now if there is some space to fill in the new archetype's partition
	if !isempty(new_to_fill)
		fill_id = to_fill[end]
		new_zone = new_zones[fill_id]
		id = new_zone.e .+1
		new_zone.e += 1
		e.ID[] = id
		swap!(t,i,id;fields=e.components)
	else
		e.ID[] = t.entity_count+1
		push!(new_zones, TableRange(t.entity_count+1, t.entity_count+1, DEFAULT_PARTITION_SIZE))
		swap!(t,i,t.entity_count+1)
		
		push(new_to_fill, length(new_zones))
	end
end

function get_entity(r::EntityRange, i::Integer)
	world = r.world.value
	id = r.s + i-1
    entities = world.table.entities
    L = r.init

    if id > r.init
    	id > length(entities) && resize!(entities, id)
    	@inbounds for j in L:id
    		entities[j] = Entity(j, r.signature, r.key, r.world; parent_ID=r.parent_id)
    	end
    	r.init = id
    else
    	return entities[id]
    end
	return world.table.entities[r.s+i]
end

get_range(t::TableRange)::UnitRange{Int64} = t.s:t.e

Base.length(t::TableRange) = clamp(t.e - t.s,0,t.size)
Base.firstindex(t::TableRange) = t.s
Base.lastindex(t::TableRange) = t.e
Base.getindex(t::TableRange,i::Int) = t.s <= i <= t.e ? i : throw(BoundsError(t,i))
Base.in(t::TableRange, i::Int) = t.s <= i <= t.e
Base.in(t::TableRange, e::Entity) = get_id(e)[] in t

#################################################### Helpers ###########################################################
_print(f, io::IO, v::TableColumn) = f(io, getfield(v, :data))
_add_zone(r::UnitRange, n::Int) = r[begin]:(r[end]+n)
