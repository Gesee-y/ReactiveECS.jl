##################################################################################################################
##################################################   MANAGER   ###################################################
##################################################################################################################

export ECSManager, SysReady
export dispatch_data, blocker, get_indices

###################################################### Core ######################################################

"""
    mutable struct WorldData
	    data::Dict{Type, StructArray}

Contains all the world data.
"""
mutable struct WorldData
	data::Dict{Symbol, VirtualStructArray}
	L::Int

	## Constructor

	WorldData() = new(Dict{Symbol, VirtualStructArray}(), 0)
end

struct ArchetypeData
	data::Vector{Int}
	positions::Dict{Int, Int}
	systems::Vector{AbstractSystem}
end

struct Queue
	add_queue::Vector{Entity}
	deletion_queue::Vector{Entity}
	data::Dict{Symbol,Vector{AbstractComponent}}

	## Constructors

	Queue() = new(Entity[], Entity[], Dict{Symbol,Vector{AbstractComponent}}())
end

mutable struct ECSManager
	entities::Vector{Optional{Entity}}
	world_data::WorldData # Contain all the data
	archetypes::Dict{BitType, ArchetypeData}
	free_indices::Vector{Int}
	queue::Queue
	blocker::Channel{Int}
	sys_count::Atomic{Int}
	sys_done::Atomic{Int}

	## Constructor

	ECSManager() = new(Vector{Optional{Entity}}(), WorldData(), Dict{BitVector, ArchetypeData}(),
		Int[], Queue(), Channel{Int}(2), Atomic{Int}(0), Atomic{Int}(0))
end

struct QueryResult
	world::WeakRef
	sys::WeakRef
end

################################################### Functions ###################################################

get_indices(ecs::ECSManager, archetype::BitType) = ecs.archetypes[archetype].data
get_indices(ecs::ECSManager, sys::AbstractSystem) = ecs.archetypes[sys.archetype].data

"""
    dispatch_data(ecs)

This function will distribute data to the systems given the archetype they have subscribed for.
"""
function dispatch_data(ecs::ECSManager)

	for archetype in values(ecs.archetypes)
		systems = get_systems(archetype)
		indices = get_data(archetype)
		isempty(indices) && continue

        ind = WeakRef(indices)
        for system in systems
		    put!(system.flow, ind)
		end
	end
end

"""
    blocker(ecs::ECSManager)

This function returns the ECSManager's blocker, which can be used with wait in order to block
"""
blocker(ecs::ECSManager) = take!(getfield(ecs, :blocker))
blocker(v::Vector{Task}) = fetch.(v)

"""
    get_component(ecs::ECSManager, s::Symbol)

This returns the SoA of a component of name `s`.
"""
get_component(ecs::ECSManager, s::Symbol) = begin 
    w::Dict{Symbol, VirtualStructArray} = ecs.world_data.data
    if haskey(w, s)
    	return w[s]
    else
    	error("ECSManager doesn't have a component $s")
    end
end

function Base.resize!(world_data::WorldData, n::Int)
	for data in values(world_data.data)
		resize!(getdata(data), n)
	end

	world_data.L = n
end

@inline Base.length(w::WorldData)::Int = getfield(w, :L)
Base.@propagate_inbounds function Base.push!(ecs::ECSManager, entity::Entity, data)
	
	w = ecs.world_data
	L = length(w)
	idx = get_id(entity)

    # If the index exceed the length of the data, we resize all the components
	if idx > L
		resize!(w, L+1)
		push!(ecs.entities, entity)
		L += 1
	else
		ecs.entities[idx] = entity
	end
    
	for key in keys(data)
		elt = data[key]

		# If the component is already in our global data
		if haskey(w.data, key)
		    w.data[key][idx] = data[key]
		# else we create a new SoA for that component and we resize it to match the other components
		else
			w.data[key] = VirtualStructArray(StructArray{typeof(elt)}(undef, L))
			w.data[key][idx] = elt
        end
	end
end

Base.@propagate_inbounds function Base.append!(ecs::ECSManager, entities::Vector{Entity}, data::Dict)

	w = ecs.world_data
	struct_data = getdata(w.data)
	L = length(w)
	add = length(entities)

    # If the index exceed the length of the data, we resize all the components
	if add > 0
		for key in keys(data)
			elt = data[key]

			# If the component is already in our global data
			if haskey(struct_data, key)
			    append!(struct_data[key], elt)
			# else we create a new SoA for that component and we resize it to match the other components
			else
				struct_data[key] = StructArray{typeof(elt[1])}(undef, 0)
				append!(struct_data[key], elt)
	        end
		end
		resize!(w, L+add)
		append!(ecs.entities, entities)
		L += add
	end
end

@inline get_free_indices(ecs::ECSManager)::Vector{Int} = getfield(ecs,:free_indices)
get_only_free_indice(ecs::ECSManager)::Int = begin
	indices = get_free_indices(ecs)
	return isempty(indices) ? 0 : pop!(indices)
end
function get_free_indice(ecs::ECSManager)::Int
    free_indices = get_free_indices(ecs)

    if !isempty(free_indices)
		return pop!(get_free_indices(ecs))
	else
		return length(ecs.world_data) + 1
	end
end

add_to_free_indices(ecs::ECSManager, i::Int) = begin
	push!(get_free_indices(ecs), i)
	ecs.entities[i] = nothing
end

@inline get_data(a::ArchetypeData) = getfield(a, :data)
@inline get_systems(a::ArchetypeData) = getfield(a, :systems)

add_to_addqueue(ecs::ECSManager, e::Entity, data::NamedTuple) = begin
    push!(ecs.queue.add_queue, e)
    for key in keys(data)
    	elt = data[key]
    	data_queue = ecs.queue.data
    	haskey(data_queue, key) ? push!(data_queue[key], elt) : (data_queue[key] = typeof(elt)[elt])
    	push!(data_queue[key], elt)
    end
end

add_to_delqueue(ecs::ECSManager, e::Entity) = push!(ecs.queue.deletion_queue, e)

Base.getindex(ecs::ECSManager, sys::AbstractSystem) = QueryResult(WeakRef(ecs), WeakRef(sys))
Base.getproperty(q::QueryResult, s::Symbol) = get_component(getfield(q, :world).value, s)

#################################################### Helpers ####################################################

_generate_name() = Symbol("Struct"*string(time_ns()))
