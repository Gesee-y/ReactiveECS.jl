#########################################################################################################################
####################################################### MANAGER #########################################################
#########################################################################################################################

######################################################## Export #########################################################

export Query, ECSManager
export @query
export dispatch_data, register_component!

######################################################### Core ##########################################################

"""
    struct Query
	    masks::Vector{UInt64}
	    partitions::Vector{TablePartitions}

This represent the result of a query. `masks` is all the mask that represent the query.
`partitions` is evry partitions that has matched the query.
"""
struct Query
    masks::Vector{UInt64}                   # Bitmasks to match
    partitions::Vector{WeakRef}     # WeakRefs to the partitions
end

"""
    @query(world, query_expr)

This search every partition in `world` that match the condition `query_expr`.

## Example

```julia

julia> @query(world, Transform & Physic | Health)
"""
macro query(world_expr, cond_expr)
    world = esc(world_expr)
    cond = cond_expr

    quote
        bitpos = $(world).table.columns

        function _to_mask(expr)
            if expr.head === :symbol
                return UInt64(1) << bitpos[expr].id
            elseif expr.head === :call
                op, args... = expr.args
                if op === :&
                    return foldl((a,b) -> a & b, map(_to_mask, args))
                elseif op === :|
                    return foldl((a,b) -> a | b, map(_to_mask, args))
                else
                    error("Unsupported operator: $op")
                end
            else
                error("Unsupported expression: $expr")
            end
        end

        masks = [_to_mask($(QuoteNode(cond)))]

        matching_parts = WeakRef[]
        for (arch_mask, part) in $(world).table.partitions
            for m in masks
                if (arch_mask & m) == m  # if the query's mask match the archetype
                    push!(matching_parts, WeakRef(part))
                    break
                end
            end
        end

        Query(masks, matching_parts)
    end
end

"""
    struct SysToken

When a system will be launched, he will have this as third argument.
So that it doesn't interfer with other possible type you would like to pass to your systems
"""
struct SysToken end

mutable struct ECSManager
	entities::Vector{Optional{Entity}}
	table::ArchTable # Contain all the data
	root::Vector{Int}
	queries::Dict{AbstractSystem, Query}
	logger::LogTracer
	blocker::Channel{Int}
	sys_count::Atomic{Int}
	sys_done::Atomic{Int}

	## Constructor

	ECSManager() = new(Vector{Optional{Entity}}(), ArchTable{UInt128}(), Int[], Dict{AbstractSystem, Query}(),
		LogTracer(), Channel{Int}(2), Atomic{Int}(0), Atomic{Int}(0))
end


################################################### Functions ###################################################

get_id(ecs::ECSManager) = -1

"""
    dispatch_data(ecs)

This function will distribute data to the systems given the archetype they have subscribed for.
"""
function dispatch_data(ecs::ECSManager)

	for (system, query) in values(ecs.archetypes)
	    put!(system.flow, query)
	end
end

"""
    blocker(ecs::ECSManager)

This function returns the ECSManager's blocker, which can be used with wait in order to block
"""
blocker(ecs::ECSManager) = take!(getfield(ecs, :blocker))
blocker(v::Vector{Task}) = fetch.(v)

register_component!(ecs::ECSManager, T::Type{<:AbstractComponent}) = register_component!(ecs.table, T)

"""
    get_component(ecs::ECSManager, s::Symbol)

This returns the SoA of a component of name `s`.
"""
get_component(ecs::ECSManager, s::Symbol) = begin 
    w::Dict{Symbol, TableColumn} = ecs.table.columns
    if haskey(w, s)
    	return w[s]
    else
    	error("ECSManager doesn't have a component $s")
    end
end

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
