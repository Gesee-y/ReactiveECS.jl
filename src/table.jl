#########################################################################################################################
####################################################### TABLE ###########################################################
#########################################################################################################################

####################################################### Export ##########################################################

export ArchTable, TableColumn
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
    TableColumn(id::Int, s::StructArray{T}) where T = new{T}(id,s)
    TableColumn{T}(id::Int,::UndefInitializer, n::Integer) where T = new{T}(id,StructArray{T}(undef, n))

end

mutable struct TablePartition
	zones::Vector{UnitRange{Int64}}
	to_fill::Vector{Int}
	size::Int64
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

function setrow!(t::ArchTable, i::Int, data::NamedTuple)
	columns::Dict{Symbol, TableColumn} = t.columns
	key = keys(data)
	@inbounds for k in key
		@inline columns[k][i] = data[k]
    end
end

function allocate_entity(t::ArchTable, n::Int, archetype::Integer)
	partitions = t.partitions
	if !haskey(partitions, archetype)
		partition = TablePartition(UnitRange{Int64}[(t.entity_count+1):(t.entity_count+n)], Int[], n)
    	partitions[archetype] = partition

    	resize!(t, length(t.entities)+n)

        return
    end
    
	partition = partitions[archetype]
	zones = partition.zones
	size = partition.size
	to_fill = zones[end][end] - size

    if to_fill > 0
    	push!(partition.to_fill, length(zone))
    end

    resize!(t, length(t.entities)+n)
    push!(zones, (t.entity_count+1):(t.entity_count+n))
end

# Create a new partition with no entity
function createpartition(t::ArchTable, archetype::Integer, size=DEFAULT_PARTITION_SIZE)
	partitions = t.partitions
	if !haskey(partitions, archetype)
		partition = TablePartition(UnitRange{Int64}[(t.entity_count+1):(t.entity_count)], Int[], size)
    	partitions[archetype] = partition
    	push!(partition.to_fill, 1)

    	resize!(t, t.entity_count+size)
    	resize!(t.entities, t.entity_count+size)
    end
end

## This will panic if there is no partitions matching that archetype
function addtopartition(t::ArchTable{T}, archetype::Integer) where T
	partitions = t.partitions
    partition = partitions[archetype]
    
    zones::Vector{UnitRange{Int64}} = partition.zones
    zone = zones[end]
    size = partition.size
    to_fill::Vector{Int} = partition.to_fill
    id = t.entity_count+1

    if !isempty(to_fill)
    	fill_id = to_fill[end]
    	zone = zones[fill_id]
    	zones[fill_id] = length(zone) == 0 ? (id:id) : _add_zone(zone,1)
    	id = zones[fill_id][end]
        
        # if we fulfilled a zone, we remove if from the zone to fill
    	id >= size && pop!(to_fill)
    else
    	push!(zones, (id):(id))
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
			zones[fill_id] -= 1
		    entities[i] = nothing
		else

		    entities[j], entities[i] = nothing, entities[j]
		    e.id, entities[i].id = j, i
		
		    swap!(t, i, j; fields=e.components)
		end

		zones[fill_id] = _add_zone(zones[fill_id],1)

		if length(zones[fill_id]) < 1
			pop!(zones)
			pop!(to_fill)
		end
	else
		partition.zones[end] = _add_zone(partition.zones[end], -1)
		entities[i] = nothing
		push(to_fill, length(partition.zones))
	end

end

function swap!(t::ArchTable, i::Int, j::Int; fields=())
    for f in fields
    	arch = t.columns[f]
    	swap!(arch, i, j)
    end
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

#################################################### Helpers ###########################################################
_print(f, io::IO, v::TableColumn) = f(io, getfield(v, :data))
_add_zone(r::UnitRange, n::Int) = r[begin]:(r[end]+n)
