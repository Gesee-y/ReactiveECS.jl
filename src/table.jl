#########################################################################################################################
####################################################### TABLE ###########################################################
#########################################################################################################################
using LoopVectorization

####################################################### Export ##########################################################

export ArchTable, TableColumn, TableRange, TablePartition
export swap!, swap_remove!, get_entity, get_range, getdata, offset

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
struct TableColumn{T}
	id::Int
    data::FragmentVector{T}
    locks::HierarchicalLock{T}

    ## Constructor
    TableColumn(id::Int, s::FragmentVector{T}) where {T} = new{T}(id,s, HierarchicalLock{T}())
    TableColumn{T}(id::Int,::UndefInitializer, n::Integer) where T = TableColumn(id,FragmentVector{T}(undef, n))
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
	const s::Int
	e::Int
	const size::Int64
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
	components::Vector{Symbol}
	fill_pos::Int
end

"""
    mutable struct ArchTable{T} where T <: Integer
		columns::Dict{Type, TableColumn}
		partitions::Dict{T, UnitRange{Int64}}

Represent a Table. `T` is the actual type used to represent an archetypes.
`columns` is a dict where each type map a component.
`partitions` is a Dict where each archetype map a compact field of components with that archetype.
"""
mutable struct ArchTable
	entities::Vector{Entity}
	columns::Dict{Symbol, TableColumn}
	partitions::ArchetypeMap{TablePartition}
	idmap::ArchetypeMap{Type}
	entity_count::Int
	component_count::Int
	row_count::Int

	## Constructors

	ArchTable() = new(Entity[], Dict{Symbol, TableColumn}(), ArchetypeMap{TablePartition}(2^15),
		ArchetypeMap{Type}(128), 0, 0, 0)
end

##################################################### Functions #########################################################

Base.eachindex(v::TableColumn) = eachindex(getdata(v))
Base.getindex(v::TableColumn, i) = getfield(v, :data)[i]
Base.setindex!(v::TableColumn, val, i) = (getdata(v)[i] = val)
Base.length(v::TableColumn) = length(getdata(v))
getdata(v::TableColumn) = getfield(v, :data)
getlocks(v::TableColumn) = getfield(v, :locks)
get_lock(v::TableColumn, path::NTuple{N,Symbol}) where N = HierarchicalLocks.get_node(getlocks(v).root, path)
get_id(t::TableColumn) = getfield(t, :id)
Base.getindex(c::TableColumn, e::Entity) = c[get_id(e)[]]
Base.setindex!(c::TableColumn, v, e::Entity) = setindex!(c, v, get_id(e)[])

"""
    register_component!(table::ArchTable, T::Type)

This register a component in a table, assigning to him a bit position.
This also initialize the column for this component. Should be done after defining the component.
"""
function register_component!(table::ArchTable, id,  T::Type)
	columns = table.columns
	key = to_symbol(T)
	count = length(table.entities)
	table.idmap[id] = T
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

function getrow(t::ArchTable, i::Int)
	res = []
	for column in values(t.columns)
		push!(res, column[i])
	end

	return res
end
function getrow(t::ArchTable, i::Int, key...)
	res = []
	for k in key
		column = t.columns[k]
		push!(res, column[i])
	end

	return res
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
function setrowrange!(t::ArchTable, range::UnitRange{Int}, data)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = keys(data)
	vals = values(data)
	l = length(range)
	m= range[begin]
	@inbounds for j in eachindex(key)
	    k = key[j]
	    v = vals[j]
	    vec = getdata(columns[k])

	    mask = vec.map[m]
	    id, offs = mask >> 32, mask & FragmentArrays.OFFSET_MASK
	    block = vec.data[id]
	    r = offset(range, offs)

	    @threads for i in r
	    	@inbounds block[i] = v
	    end
	end
end
function setrowrange!(t::TableColumn, vec, c)
	col = getdata(t)

	for id in vec
		col[id[]] = c
	end
end
function setrowrange!(idx, columns, v)
	for x in idx
		i = x[]
		for j in eachindex(v)
			col = getdata(columns[j])
			col[i] = v[j]
		end
	end
end
@generated function setrowrange!(idx, columns, v, ::Val{N}) where {N}
    expr = Expr(:block)
    swaps = expr.args
    colsym = []
    valsym = []

    for i in 1:N
    	push!(colsym, gensym())
    	push!(valsym, gensym())
    	s = colsym[end]
    	vs = valsym[end]
    	push!(swaps, :($s = columns[$i]; $vs = v[$i]))
    end
    body = quote end

    for i in eachindex(colsym)
    	vs = valsym[i]
    	col = colsym[i]

    	push!(body.args, :($col[$i] = $vs))
    end
	
    push!(swaps, quote
    	for x in idx
    		i = x[]
    	    @inbounds $body
    	end
    end)

    return expr
end

function fsetrowrange!(t::ArchTable, r::UnitRange{Int}, data)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = keys(data)
	vals = values(data)
	@inbounds for j in eachindex(key)
	    k = key[j]
	    v = vals[j]
	    vec = getfield(columns[k],:data)
 	    for i in r
	    	vec[i] = _value(v, i)
	    end
	end
end

"""
    allocate_entity(t::ArchTable, n::Int, archetype::Integer; offset=2048)

This will allocate `n` entities in the table `t`. More precisely for the partition of the given `archetype`
`offset` is how many entities will be allocated in case the allocation left half-filled ranges.
This function return a set of interval corresponding to the indices of entities allocated.
"""
function allocate_entity(t::ArchTable, n::Int, archetype::Integer; offset=DEFAULT_PARTITION_SIZE)
	partitions = t.partitions
	intervals = UnitRange{Int64}[]

	# If the partition fot that archetype doesn't yet exist
	if !haskey(partitions, archetype)
		# Just creating a new partition
		comps = get_components_list(t, archetype)
		range = t.row_count+1:t.row_count+n
		columns = t.columns
		partition = TablePartition(TableRange[TableRange(t.row_count+1,t.row_count+n, n)], Int[], comps, 1)
    	partitions[archetype] = partition # And creating that new archetype

        push!(intervals, t.row_count+1:t.row_count+n)
        resize!(t, t.row_count+n+1)

        for c in comps
        	prealloc_range(getdata(columns[c]), range)
        end

        t.entity_count += n
    	
        return intervals
    end
    
	partition = partitions[archetype]
	zones = partition.zones
	part_to_fill = partition.to_fill
    m = n # Entity left to be added

	count = partition.fill_pos
	l = length(zones)

    # While there are still entities to add and there are still ranges to fill
	while m > 0 && count <= l
		zone = zones[count]
		size = zone.size

		# The number of entities needed to fill this
		to_fill = size - length(zone) 
		v = clamp(m,0,to_fill)

		# If there are more entities to add than space available, then that zone is filled
		m >= to_fill && (partition.fill_pos += 1)

        ed = max(zone.e, 1)
		zone.e += v
        # We then add to interval our newly filled zone
		push!(intervals, ed:(zone[end]))
		

		m -= to_fill
		count += 1
	end

    # If after all that there is still some entities to add
	if m > 0
		# We create a new range for it with the given offset
		size = max(m, offset)
		comps = get_components_list(t, archetype)
		range = t.row_count+1:t.row_count+size+1
		columns = t.columns
		push!(zones, TableRange(t.row_count+1, t.row_count+m, size))
		push!(intervals, t.row_count+1:t.row_count+m)
		partition.fill_pos = length(zones)
	    
	    nsize = t.row_count+size
		resize!(t, nsize+1) # Finally we just resize our table

		for c in comps
        	prealloc_range(getdata(columns[c]), range)
        end
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
		comps = get_components_list(t, archetype)
		columns = t.columns
		partition = TablePartition(TableRange[TableRange(t.row_count+1,t.row_count, size)], Int[1], comps, 1)
    	partitions[archetype] = partition

    	for c in comps
        	prealloc_range(getdata(columns[c]), t.row_count+1:t.row_count+size)
        end

    	resize!(t, t.row_count+size+1)
    end
end

"""
    addtopartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)

This add a new slot to a partition or create another range if necessary and return the newly created id.
This will panic if there is no partitions matching that archetype
"""
function addtopartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)
	partitions = t.partitions
    partition = partitions[archetype]
    comps = partition.components
    
    zones::Vector{TableRange} = partition.zones
    fill_id = min(partition.fill_pos, length(zones))
    last_zone = zones[fill_id]
    id = t.row_count+1


    # if there is some zone to fill
    if !isfull(last_zone)
    	last_zone.e += 1
    	id = last_zone[end]
    else
    	# We create a new range and add it to the one to be filled
    	if fill_id < length(zones)
    		zones[fill_id+1].e += 1
    		id = zones[fill_id+1].e
    	else
    		columns = t.columns
    		push!(zones, TableRange(id,id,size))
    		resize!(t, id+size)
    		for c in comps
        	    prealloc_range(getdata(columns[c]), id:id+size)
            end
    	end
    	partition.fill_pos += 1
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
	entities = t.entities
	zones = partition.zones
	last_zone = zones[end]

	i = get_id(e)[]
    
    # If there are some zone to fill
	if !hasonlyoneelt(last_zone)
		j = last_zone[end]

        # If the last index is the same as i then we can just shrink the zone
		if i == j
			entities[last_zone.e].alive = false
			last_zone.e -= 1
		else
			# We check this in case the entity is undefined du to some resizing
			if !isdefined(entities, j)
				ei = entities[i]
				empty!(ei.children)
		    else
			    entities[i] = entities[j]
			    e.ID[], entities[i].ID[] = j, i
			    e.alive = false
			end

			swap!(t, i, j; fields=e.components)
		end
	else
		j = partition.zones[end][end]
		swap!(t, i, j; fields=e.components)
		partition.zones[end].s -= 1
		entities[i] = entities[j]
	    e.ID[], entities[i].ID[] = j, i
	    e.alive = false
		
		pop!(partition.zones)
	end

    t.entity_count -= 1

	for ids in e.children
		child = entities[ids[]]
		swap_remove!(t, child)
	end
end

function override_remove!(t::ArchTable, e::Entity)
	partition = t.partitions[e.archetype] 
	components = partition.components
	f = partition.fill_pos
	entities = t.entities
	zones = partition.zones
	last_zone = zones[f]

	i = get_id(e)[]
    
    # If there are some zone to fill
	if !hasonlyoneelt(last_zone)
		j = last_zone[end]

        # If the last index is the same as i then we can just shrink the zone
		if i == j
			entities[last_zone.e].alive = false
			last_zone.e -= 1
		else
			# We check this in case the entity is undefined du to some resizing
			if !isdefined(entities, j)
				ei = entities[i]
				empty!(ei.children)
		    else
			    entities[i] = entities[j]
			    e.ID[], entities[i].ID[] = j, i
			    e.alive = false
			end

			override!(t, i, j, components)
		end
	else
		j = partition.zones[end][end]
		override!(t, i, j, components)
		partition.zones[end].s -= 1
		entities[i] = entities[j]
	    e.ID[], entities[i].ID[] = j, i
	    e.alive = false
		
		partition.fill_pos -= 1
	end

    t.entity_count -= 1

	for ids in e.children
		child = entities[ids[]]
		override_remove!(t, child)
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
function swap!(cols::TableColumn{T}, i::Int, j::Int) where T
	arch = getdata(cols)
	arch[i], arch[j] = arch[j], arch[i]
end
@generated function override!(arch::TableColumn{T}, i::UnitRange, j, s=1) where T
    data = getdata(arch)
    @inbounds for x in s:length(i)
        data[i[x]] =  data[j[x]]
    end
end

function override!(t::ArchTable, i::Int, j::Int,fields::Vector{Symbol})
    columns = t.columns
    for f in fields
    	arch = columns[f]
    	override!(arch, i, j)
    end
end
function swap_override!(t::ArchTable, sw, i, j,fields::Vector{Symbol}, s=1)
    columns = t.columns
    for f in fields
    	arch = columns[f]
    	swap_override!(arch, sw, i, j, s)
    end
end

function override!(t::ArchTable, e1::Entity, e2::Entity)
	i, j = get_id(e1)[], get_id(e2)[]
	override!(t, i, j, fields=e1.components)
end
function override!(arch::TableColumn{T}, i::Int, j::Int) where T
    data = getdata(arch)
    data[i] = data[j]
end
function override!(arch::TableColumn{T}, i::UnitRange, j::Int) where T
    data = getdata(arch)
    Threads.@threads for x in i
        data[x] = data[j]
    end
end
function swap_override!(arch::TableColumn{T},sw , i::UnitRange, j, s=1) where {T}
	col = getdata(arch)
    for x in s:length(i)
    	a, b, c = i[x], j[x][], sw[x]
    	id = col.map[c] >> 32
    	id2 = col.map[b] >> 32
    	!iszero(id2) && (col[a] = col[b])
    	!iszero(id) && (col[b] = col[c])
    end
end

"""
    change_archetype(t::ArchTable, e::Entity, archetype::Integer)

Move the entity `e` of the table `t` from his archetype to a new `archetype`.
This function assume `t` contain a partition for `archetype` else it will panic.
"""

function change_archetype!(t::ArchTable, e::Entity, old_arch::Integer, new_arch::Integer)
    partitions = t.partitions
    # Ensure new partition exists
    createpartition(t, new_arch)

    old_partition = partitions[old_arch]
    new_partition = partitions[new_arch]

    fields = old_partition.components
    entities = t.entities

    f1 = old_partition.fill_pos
    f2 = new_partition.fill_pos

    old_zone = old_partition.zones[end]
    new_zone = new_partition.zones[f2]

    i = get_id(e)[]

    # Remove from old zone (get last valid entity)
    j = old_zone.e
    old_zone.e -= 1

    # Allocate slot in new zone
    if new_zone.e-new_zone.s+1 == new_zone.size
        # Extend partition with new zone
        if f2 < length(new_partition.zones)
        	nz = new_partition.zones[f2+1]
        	nz.e += 1
            new_id = nz.e
        else
            push!(new_partition.zones, TableRange(t.row_count+1, t.row_count+1, DEFAULT_PARTITION_SIZE))
            for c in fields
        	    prealloc_range(getdata(t.columns[c]), t.row_count+1:t.row_count + DEFAULT_PARTITION_SIZE)
            end
            new_id = t.row_count+1

            resize!(t, t.row_count + DEFAULT_PARTITION_SIZE+1)
            
        end
        new_partition.fill_pos += 1
    else
        new_id = new_zone.e + 1
        new_zone.e += 1
    end

    e.ID[] = new_id
    entities[new_id] = e

    # Swap structs directly
    begin
        for f in fields
            col = t.columns[f]
            override!(col, new_id, i)
            override!(col, i, j)
        end
    end

    # Finalize old slot
    if i != j
        if !isdefined(entities, j)
	        entities[j] = Entity(j, old_arch, e.world)
        end
	    
        entities[i] = entities[j]
        entities[j].ID[] = i
    end
end
function change_archetype!(t::ArchTable, entities::Vector{Entity}, old_arch, new_arch, new=true)
    partitions = t.partitions
    createpartition(t, new_arch)

    old_partition::TablePartition = partitions[old_arch]
    new_partition::TablePartition = partitions[new_arch]

    f1 = old_partition.fill_pos
    f2 = new_partition.fill_pos

    old_zones::Vector{TableRange} = old_partition.zones
    new_zones::Vector{TableRange} = new_partition.zones

    l2 = length(new_partition.zones)
    fields = new ? new_partition.components : old_partition.components

    old_zone = old_zones[end]
    new_zone = new_zones[end]
    
    n = length(entities)
    to_fill = UnitRange{Int}[]

    to_swap = Int[]
    
    m = n
    p = n
    mids = get_id.(entities)

    while p > 0 && f1 > 0
    	zone = old_zones[f1]
    	count = zone.e - zone.s + 1
    	p -= count
    	append!(to_swap, get_range(zone))
    	zone.e -= min(count, p)
    	f1 -= 1
    end
    old_partition.fill_pos = max(f1, 1)

    while m > 0 && f2 <= l2
    	zone = new_zones[f2]

    	endval = zone.s + min(m,zone.size) - 1
    	r = zone.e+1:endval
    	
    	m -= length(r)
    	push!(to_fill, r)
    	zone.e = endval

    	f2 += 1
    end

    if m > 0
    	# Extend partition with new zone
    	size = max(DEFAULT_PARTITION_SIZE, m)
        push!(new_zones, TableRange(t.row_count+1, t.row_count+m, size))
        
        push!(to_fill, t.row_count+1:(t.row_count+m))
        for c in fields
        	prealloc_range(getdata(t.columns[c]), t.row_count+1:t.row_count + size)
        end
        resize!(t, t.row_count + size+1)
    end

    new_partition.fill_pos = min(f2, l2)
    columns = t.columns
    
    s = 1
    for r in to_fill
    	swap_override!(t, to_swap, r, mids, fields, s)
    	s += length(r)
    end

    c = 1
    @inbounds for r in to_fill
        for i in r
        	e = entities[c]
        	id = mids[c]
        	
            id[] = i
            t.entities[i] = e
            e.archetype = new_arch
            c += 1
        end
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

get_range(t::TableRange, offset=0)::UnitRange{Int64} = t.s-offset:t.e-offset

function get_components_list(t::ArchTable, archetype::Integer)
	res = Symbol[]
    
    while archetype != 0
    	bit = archetype & (~archetype + 1)
    	push!(res, Symbol(t.idmap[bit]))

    	archetype = xor(archetype, bit)
    end

    return res
end

offset(r::UnitRange, offset) = r[begin]-offset:r[end]-offset
Base.length(t::TableRange) = clamp(t.e - t.s + 1,0,t.size)
Base.firstindex(t::TableRange) = t.s
Base.lastindex(t::TableRange) = t.e
Base.getindex(t::TableRange,i::Int) = t.s <= i <= t.e ? i : throw(BoundsError(t,i))
Base.in(t::TableRange, i::Int) = t.s <= i <= t.e
Base.in(t::TableRange, e::Entity) = get_id(e)[] in t
isfull(t::TableRange) = length(t) == t.size
hasonlyoneelt(t::TableRange) = length(t) == 1
#################################################### Helpers ###########################################################

_value(x::Any, i::Int) = x
_value(f::Function, i::Int) = f(i)
_print(f, io::IO, v::TableColumn) = f(io, getfield(v, :data))
_add_zone(r::UnitRange, n::Int) = r[begin]:(r[end]+n)
