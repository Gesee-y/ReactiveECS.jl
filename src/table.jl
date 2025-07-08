#########################################################################################################################
####################################################### TABLE ###########################################################
#########################################################################################################################
using BenchmarkTools

####################################################### Export ##########################################################

export ArchTable, TableColumn, TableRange
export swap!, swap_remove!, get_entity

######################################################## Core ###########################################################

const DEFAULT_PARTITION_SIZE = 2^12

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
    	data::StructArray{T}

This represent a column of the table. A column is in a fact a Struct of array where each field is a vector where each
index is an entity.
"""
struct TableColumn{T}
	id::Int
    data::StructArray{T}

    ## Constructor
    TableColumn(id::Int, s::StructArray{T}) where {T} = new{T}(id,s)
    TableColumn{T}(id::Int,::UndefInitializer, n::Integer) where T = TableColumn(id,StructArray{T}(undef, n))
end

mutable struct TableRange
	s::Int
	e::Int
	size::Int64
end

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

	## Constructors

	ArchTable{T}() where T = new{T}(Optional{Entity}[], Dict{Symbol, TableColumn}(), Dict{T, TablePartition}(), 0, 0)
end

##################################################### Functions #########################################################

Base.eachindex(v::TableColumn) = eachindex(getdata(v))
Base.getindex(v::TableColumn, i) = getdata(v)[i]
Base.setindex!(v::TableColumn, val, i) = (getdata(v)[i] = val)
getdata(v::TableColumn) = getfield(v, :data)
get_id(t::TableColumn) = getfield(t, :id)
Base.getproperty(v::TableColumn, s::Symbol) = get_field(v, Val(s))

function register_component!(table::ArchTable, T::Type)
	columns = table.columns
	key = to_symbol(T)
	count = length(table.entities)
	!haskey(columns, key) && (table.component_count+=1; 
		columns[key] = TableColumn{T}(table.component_count, undef, count))
end

function initrow!(t::ArchTable, data::NamedTuple)
	columns = t.columns
	count = t.entity_count+1
	for key in keys(data)
		!haskey(columns, key) && (t.component_count+=1; 
			columns[key] = TableColumn{typeof(data[key])}(t.component_count, undef, count))
	end
end

function addrow!(t::ArchTable, data::NamedTuple)
	columns = t.columns
	count = t.entity_count+1
	resize!(t, count)
	for key in keys(data)
		elt = data[key]
		columns[key][count] = data[key]
    end
end

function setrow!(t::ArchTable, i::Int, data)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = keys(data)
	vals = values(data)
	@inbounds for j in eachindex(key)
	    k = key[j]
	    getfield(columns[k],:data)[i] = vals[j]
	end
end

function allocate_entity(t::ArchTable, n::Int, archetype::Integer; offset=2048)
	partitions = t.partitions
	intervals = UnitRange{Int64}[]
	if !haskey(partitions, archetype)
		partition = TablePartition(TableRange[TableRange(t.entity_count+1,t.entity_count+n, n)], 
			Int[])
    	partitions[archetype] = partition

    	resize!(t, length(t.entities)+n)

        return
    end
    
	partition = partitions[archetype]
	zones = partition.zones
	part_to_fill = partition.to_fill
    m = n

	count = length(part_to_fill)

	while m > 0 && count > 0
		i = part_to_fill[count]
		zone = zones[count]
		size = zone.size
		to_fill = size - length(zone)
		v = clamp(m,0,to_fill)

		m >= to_fill && pop!(part_to_fill)

		push!(intervals, zone[end]:(zone[end]+v))
		zone.e += v

		m -= to_fill
		count -= 1
	end

	if m > 0
		push!(zones, TableRange(t.entity_count+1, t.entity_count+m+offset, m+offset))
		push!(part_to_fill, length(zones))
	end

    resize!(t, length(t.entities)+n)

    return intervals
end

# Create a new partition with no entity
function createpartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)
	partitions = t.partitions
	if !haskey(partitions, archetype)
		partition = TablePartition(TableRange[TableRange(t.entity_count+1,t.entity_count, size)], Int[])
    	partitions[archetype] = partition
    	push!(partition.to_fill, 1)

    	resize!(t, t.entity_count+size)
    	resize!(t.entities, t.entity_count+size)
    end
end

## This will panic if there is no partitions matching that archetype
function addtopartition(t::ArchTable{T}, archetype::Integer, size=DEFAULT_PARTITION_SIZE) where T
	partitions = t.partitions
    partition = partitions[archetype]
    
    zones::Vector{TableRange} = partition.zones
    zone = zones[end]
    to_fill::Vector{Int} = partition.to_fill
    id = t.entity_count+1

    if !isempty(to_fill)
    	fill_id = to_fill[end]
    	zone = zones[fill_id]
    	zone.e += 1
    	id = zone[end]
        
        # if we fulfilled a zone, we remove if from the zone to fill
    	id >= size && pop!(to_fill)
    else
    	push!(zones, TableRange(id,id,size))
    	push!(to_fill, length(zones))
    	resize!(t, id+size-1)
    end

    return id
end

get_column(t::ArchTable, field::Symbol) = t.columns[field]

function Base.resize!(t::ArchTable, n::Int)
    columns = t.columns
    resize!(t.entities, n)
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

	i = get_id(e)

	if !isempty(to_fill)
		fill_id = to_fill[end]

		j = zones[fill_id][end]

		if i == j
			zones[fill_id].e -= 1
		    entities[i] = nothing
		else
			if !isdefined(entities, j)
				entities[i] = Entity(i, e.archetype, e.components, e.world, -1, Int[])
				entities[j] = nothing
		    else
			    entities[j], entities[i] = nothing, entities[j]
			    e.ID, entities[i].ID = j, i
			
			    swap!(t, i, j; fields=e.components)
		    end
		end

		if length(zones[fill_id]) < 1
			pop!(zones)
			pop!(to_fill)
		end
	else
		partition.zones[end].s -= 1
		entities[i] = nothing
		push(to_fill, length(partition.zones))
	end

	for c in get_children(e)
		child =  entities[c]
		child != nothing && swap_remove!(t, child)
    end
end

function swap!(t::ArchTable, i::Int, j::Int; fields=())
    for f in fields
    	arch = t.columns[f]
    	swap!(arch, i, j)
    end
end
function swap!(t::ArchTable, e1::Entity, e2::Entity)
	i, j = get_id(e1), get_id(e2)
	swap!(t, i, j, fields=e.components)
	e1.ID, e2.ID = j, i
end
@generated function swap!(arch::TableColumn{T}, i::Int, j::Int) where T
    fields=fieldnames(T)
    expr = Expr(:block)
    swaps = expr.args
    for f in fields
    	type = fieldtype(T, f)
    	data = gensym()
        push!(swaps, :($data::Vector{$type} = arch.$f; $data[i],  $data[j] =  $data[j],  $data[i]))
    end

    return expr
end

function change_archetype(t::ArchTable, e::Entity, archetype::Integer)
    partition = t.partitions[e.archetype]
    new_partition = t.partitions[archetype]
	new_to_fill = new_partition.to_fill
	new_zones = new_partition.zones 
    to_fill = partition.to_fill
	entities = t.entities
	zones = partition.zones

	i = get_id(e)

    zone = zones[end]
	j = zone[end]
	swap!(t,e,entities[j])
	zone.e -= 1
	
	if !isempty(new_to_fill)
		fill_id = to_fill[end]
		new_zone = new_zones[fill_id]
		id = new_zone[end] +1
		new_zone.e += 1
		e.ID = id
		swap!(t,i,id;fields=e.components)
	else
		e.ID = t.entity_count+1
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
    		entities[j] = Entity(j, r.signature, r.key, r.world, r.parent_id, UInt[])
    	end
    	r.init = id
    else
    	return entities[id]
    end
	return world.table.entities[r.s+i]
end

Base.length(t::TableRange) = clamp(t.e - t.s,0,t.size)
Base.firstindex(t::TableRange) = t.s
Base.lastindex(t::TableRange) = t.e
Base.getindex(t::TableRange,i::Int) = 0 <= i <= length(t)+1 ? t.s+i-1 : throw(BoundsError(t,i))
Base.in(t::TableRange, i::Int) = t.s <= i <= t.e
Base.in(t::TableRange, e::Entity) = get_id(e) in t

#################################################### Helpers ###########################################################
_print(f, io::IO, v::TableColumn) = f(io, getfield(v, :data))
_add_zone(r::UnitRange, n::Int) = r[begin]:(r[end]+n)
