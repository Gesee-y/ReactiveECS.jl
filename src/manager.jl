#########################################################################################################################
####################################################### MANAGER #########################################################
#########################################################################################################################

######################################################## Export #########################################################

export Query, ECSManager, SysToken
export @query, @foreachrange
export dispatch_data, register_component!, get_component, blocker, get_lock

######################################################### Core ##########################################################

"""
    struct Query
	    masks::Vector{UInt64}
	    partitions::Vector{TablePartitions}

This represent the result of a query. `masks` is all the mask that represent the query.
`partitions` is evry partitions that has matched the query.
"""
mutable struct Query
    masks::Vector{NTuple{2, UInt128}}         # Bitmasks to match
    partitions::Vector{Tuple{WeakRef,TablePartition}}  # WeakRefs to the partitions
end

"""
    @query(world, query_expr)

This search every partition in `world` that match the condition `query_expr`.

## Example

```julia

julia> @query(world, Transform & Physic & ~Health)
"""
macro query(world_expr, cond_expr)
    world = esc(world_expr)
    cond = QuoteNode(cond_expr)

    quote
        tables = get_tables($(world))
        bitpos = $(world).components_ids
        mask,exclude = _to_mask(bitpos,$cond)
        matching_parts::Vector{Tuple{WeakRef,TablePartition}} = Tuple{WeakRef,TablePartition}[]
        for table in values(tables)
            for (arch_mask, part) in table.partitions
                if ((arch_mask & mask) == mask) && (arch_mask & exclude) == arch_mask
                    push!(matching_parts, (WeakRef(table),part))
                end
            end
        end

        Query(NTuple{2, UInt128}[(mask, exclude)], matching_parts)
    end
end

macro foreachrange(query, body)
    return esc(quote
        for partition in $query
            TABLE = partition[1].value
            zones::Vector{TableRange} = partition[2].zones

            for zone in zones
                range = get_range(zone)

                $body
            end
        end
    end)
end

"""
    struct SysToken

When a system will be launched, he will have this as third argument.
So that it doesn't interfer with other possible type you would like to pass to your systems
"""
struct SysToken end

mutable struct ECSManager
	entities::Vector{Optional{Entity}}
	tables::Dict{Symbol,ArchTable} # Contain all the data
	main::Symbol
    components_ids::Dict{Symbol, Int}
    bitpos::Int
    root::Vector{Int}
	queries::Dict{AbstractSystem, Query}
	logger::LogTracer
	sys_count::Atomic{Int}
	sys_done::Atomic{Int}
    blocker::Condition

	## Constructor

	ECSManager() = new(Vector{Optional{Entity}}(), Dict{Symbol,ArchTable}(:main => ArchTable()), :main, 
        Dict{Symbol, Int}(), 1, Int[], Dict{AbstractSystem, Query}(), LogTracer(), Atomic{Int}(0), Atomic{Int}(0), 
        Condition())
    ECSManager(args...) = begin
        ecs = ECSManager()
        for arg in args
            register_component!(ecs, arg)
        end

        return ecs
    end
end


################################################### Functions ###################################################

get_id(ecs::ECSManager) = -1
get_lock(ecs::ECSManager, symb::Symbol, path) = get_lock(get_component(ecs, symb), path)
get_tables(ecs::ECSManager) = ecs.tables
get_table(ecs::ECSManager) = ecs.tables[ecs.main]

"""
    dispatch_data(ecs)

This function will distribute data to the systems given the archetype they have subscribed for.
"""
function dispatch_data(ecs::ECSManager)
    queries::Dict{AbstractSystem, Query} = ecs.queries
	for system in keys(queries)
        put!(system.flow, queries[system])
	end
end

"""
    blocker(ecs::ECSManager)

This function returns the ECSManager's blocker, which can be used with wait in order to block
"""
blocker(ecs::ECSManager) = wait(ecs.blocker)
blocker(v::Vector{Task}) = fetch.(v)

"""
    register_component!(ecs::ECSManager, T::Type{<:AbstractComponent})

Register the a component in the manager `ecs.
This will create a column for that component in a world.
"""
register_component!(ecs::ECSManager, T::Type{<:AbstractComponent}) = begin 
    if !haskey(ecs.components_ids, Symbol(T))
        ecs.components_ids[Symbol(T)] = ecs.bitpos
        ecs.bitpos += 1
    end

    register_component!(get_table(ecs),1 << ecs.components_ids[Symbol(T)], T)
end

"""
    get_component(ecs::ECSManager, s::Symbol)

This returns the SoA of a component of name `s`.
"""
get_component(ecs::ECSManager, s::Symbol) = begin 
    w = get_table(ecs).columns
    return w[s]
end
get_component(ecs::ECSManager, T::Type) = get_component(ecs, to_symbol(type))

Base.iterate(q::Query, i=1) = i > length(q.partitions) ? nothing : (q.partitions[i], i+1)

NodeTree.get_children(ecs::ECSManager)::Vector{Int} = get_root(ecs)
NodeTree.get_root(ecs::ECSManager)::Vector{Int} = getfield(ecs, :root)
NodeTree.add_child(ecs::ECSManager, e::Entity) = push!(get_root(ecs), get_id(e))
NodeTree.get_node(ecs::ECSManager, i::Int) = i > 0 ? ecs.entities[i] : ecs.root
function NodeTree.print_tree(io::IO,ecs::ECSManager;decal=0,mid=1,charset=get_charset())
	childrens = get_children(ecs)

	print("ECSManager with $(length(ecs.world_data)) Nodes : ")

	for i in eachindex(childrens)
		println()
		child = get_node(ecs,childrens[i])

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

function _to_mask(bitpos, expr, exclude=typemax(UInt128))
    if expr isa Symbol
        return (UInt128(1) << bitpos[expr], exclude)
    elseif expr isa Expr
        if expr.head === :call
            op, args... = expr.args
            if op === :&
                a,b = _to_mask(bitpos,args[1],exclude), _to_mask(bitpos,args[2],exclude)
                return (a[1] | b[1], a[2] & b[2])
            elseif op === :~
                exclude &= ~_to_mask(bitpos,args[1])[1]
                return (0, exclude)
            else
                error("Unsupported operator in query: $op")
            end
        else
            error("Unsupported expression head: $(expr.head)")
        end
    else
        error("Invalid expression in query: $expr")
    end
end

