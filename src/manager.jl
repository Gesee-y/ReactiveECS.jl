##################################################################################################################
##################################################   MANAGER   ###################################################
##################################################################################################################

export ECSManager
export dispatch_data

###################################################### Core ######################################################

"""
    mutable struct WorldData
	    data::Dict{Type, StructArray}

Contains all the world data.
"""
mutable struct WorldData
	data::Dict{Symbol, StructArray}
	L::Int

	## Constructor

	WorldData() = new(Dict{Symbol, StructArray}(), 0)
end

struct ArchetypeData
	data::Vector{Int}
	systems::Vector{AbstractSystem}
end

mutable struct ECSManager
	entities::Vector{Optional{Entity}}
	world_data::WorldData # Contain all the data
	archetypes::Dict{BitType, ArchetypeData}
	free_indices::Vector{Int}

	## Constructor

	ECSManager() = new(Vector{Optional{Entity}}(), WorldData(), Dict{BitVector, ArchetypeData}(), Int[])
end

################################################### Functions ###################################################

"""
    dispatch_data(ecs)

This function will distribute data to the systems given the archetype they have subscribed for.
"""
function dispatch_data(ecs::ECSManager)
    
    ref = WeakRef(ecs.world_data.data)
	for archetype in values(ecs.archetypes)
		systems::Vector{AbstractSystem} = get_systems(archetype)
        ind = WeakRef(get_data(archetype))

		for system in systems
		    put!(system.flow, (ref, ind))
		end
	end
end

function Base.resize!(world_data::WorldData, n::Int)
	for key in keys(world_data.data)
		resize!(world_data.data[key], n)
	end

	world_data.L = n
end

Base.length(w::WorldData) = getfield(w, :L)
function Base.push!(ecs::ECSManager, entity, data)
	w = ecs.world_data
	L = length(w)
	idx = get_id(entity)

	idx > L ? (resize!(w, length(w)+1); push!(ecs.entities, entity)) : (ecs.entities[idx] = entity)

	for key in keys(data)
		elt = data[key]
		if haskey(w.data, key)
		    w.data[key][idx] = data[key]
		else
			L = length(w)
			w.data[key] = StructArray{typeof(elt)}(undef, length(w))
			w.data[key][idx] = elt
        end
	end
end

get_free_indices(ecs::ECSManager) = getfield(ecs,:free_indices)
function get_free_indice(ecs::ECSManager)
    free_indices = get_free_indices(ecs)

    if !isempty(free_indices)
		return pop!(get_free_indices(ecs))
	else
		return length(ecs.world_data) + 1
	end
end

add_to_free_indices(ecs::ECSManager, i::Int) = (push!(get_free_indices(ecs), i); ecs.entities[i] = nothing)

get_data(a::ArchetypeData) = getfield(a, :data)
get_systems(a::ArchetypeData) = getfield(a, :systems)

#################################################### Helpers ####################################################

_generate_name() = Symbol("Struct"*string(time_ns()))