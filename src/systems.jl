##################################################################################################################
###################################################   SYSTEM   ###################################################
##################################################################################################################

export @system
export subscribe!, unsubscribe!, listen_to
export run!, run_system!

const SYS_CHANNEL_SIZE = Inf
"""
    @system sys_name

This macro serve to create a new system . You can initialize it with just `sys_name()`.
"""
macro system(name)
	return quote
		mutable struct $name <: AbstractSystem
			active::Bool
			flow::Channel
			archetype::BitType
			position::Int
			children::Vector{AbstractSystem}
			
			## Constructors

			$name() = new(true,Channel(SYS_CHANNEL_SIZE), init(BitType), 0, AbstractSystem[])
		end
	end
end


############################################### System Management ################################################

"""
    run!(sys::T, data) where T <: AbstractSystem

This function should be overloaded for every system. It's the task they will execute
If the system have subscribed to the manager, `data` will be a tuple, were the 1st is a weak references to the data
and the 2nd is a weak references to the indices of the entities requested by the system
"""
run!(sys::T, batch) where T <: AbstractSystem = error("run! is not defined for the system of type $T")

function run_system!(@nospecialize(system::AbstractSystem))
    
    # The system will run as an asynchronous task
    # We can stop it at anytime with system.active
	@async while system.active
		batch = take!(system.flow)

		try
		    result = run!(system, batch)

			children = system.children
			
			if result != nothing
				feed_children(system, result)
			end
	    catch e
	    	system.active = false
	    	@warn "The system $(typeof(system)) encountered an error: $e"
	    end
	end
end

function feed_children(@nospecialize(sys::AbstractSystem), data)
	children = sys.children
		
	for child in children
		put!(child.flow, data)
	end
	
end

"""
    listen_to(source::AbstractSystem, listener::AbstractSystem)

This function make the system `listener` wait for data coming from the system `source`
"""
@inline Base.@nospecializeinfer function listen_to(@nospecialize(source::AbstractSystem), @nospecialize(listener::AbstractSystem))

	## We will skip error checking on purpose
	# We are just fetching data so there should be not problem
	# We will just async this to ensure that we are still on the main thread
    _check_cycle(source, listener)
    push!(source.children, listener)
end

"""
    listen_to(ecs::ECSManager, archetype::NTuple{N,Symbol}, listener::AbstractSystem, num=1) where N

This function will make the system `listener` wait for data coming the `num` systems who have request the components `archetype`
"""
function listen_to(ecs::ECSManager, components::Tuple, listener::AbstractSystem, num=1)
	archetype = get_bits(components)
	if haskey(ecs.archetypes, archetype)
		source = get_systems(ecs.archetypes[archetype])

		(num == -1) && (num = length(source))
		for i = 1:num
		    listen_to(source[i], listener)
		end
	else
		@warn "There is no system matching the archetype $archetype yet."
	end
end

"""
    subscribe!(ecs::ECSManager, system::AbstractSystem, components::Tuple)

This function makes the system subscribe to a set of archetype.
`component` is a tupe of type, each type is a component's type
"""
function subscribe!(ecs::ECSManager, system::AbstractSystem, components::Tuple)
	
	# If the is not system with a subscription to the given archetype
	archetype = get_bits(BitType,components)
	
	if !haskey(ecs.archetypes, archetype)

		# Setting some little hooks
		system.archetype = archetype
		system.position = 1
		indices = Int[]

		# Creating the new data for the archetype
		archetype_data = ArchetypeData(indices, AbstractSystem[system])
		ecs.archetypes[archetype] = archetype_data

		# We will now put all the entities matching that archetype in indices
		for entity in ecs.entities
			if _match_archetype(entity, archetype)
				push!(indices, get_id(entity))
				entity.positions[archetype] = length(indices)-1
			end
		end
	else
		systems = get_systems(ecs.archetypes[archetype])
		push!(systems, system)
		system.position = length(systems)
	end

	return nothing
end

"""
    unsubscribe!(ecs::ECSManager, system::AbstractSystem)

This function will make a system stop waiting for data from a given archetype
"""
function unsubscribe!(ecs::ECSManager, system::AbstractSystem)
	deleteat!(get_systems(ecs.archetypes[system.archetype]), system.position)
end

################################################# Helpers ######################################################

function _check_cycle(source, listener)
	(source == listener) && error("Cycle detected in listen_to($source, $listener)")
	for child in source.children
		_check_cycle(child, listener)
	end
end