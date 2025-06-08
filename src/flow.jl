################################################# Data flow ####################################

#=
    Let's start by making a simple thing. a flow is a channel, in which we put and take data
    Since taking and putting is kind of costly, we will batch them, meaning we send a bunch of data
    instead of individual data.
=#

mutable struct DataFlow{T}
	input::Channel{T}
	output::Channel{T}

    ## Constructors
	DataFlow{T}() where T = new{T}(Channel{T}(Inf), Channel{T}(Inf))
end

"""
    @system(name, type)

This macro create a new system and the given name and will process data of type `type`
"""
macro system(name, type)
	return quote
		mutable struct $name <: AbstractSystem
			active::Bool
			flow::DataFlow{WeakRef}
			children::Vector{AbstractSystem}

			## Constructors

			$name() = new(true,DataFlow{WeakRef}(),AbstractSystem[])
		end
	end
end

"""
    dispatch_data(ecs)

This function will distribute data to the systems given the archetype they have subscribed for.
"""
function dispatch_data(ecs)
	for archetype in keys(ecs.systems)
		data = ecs.groups[archetype]
		systems = ecs.systems[archetype]

		for system in systems
		    put!(system.flow.input, WeakRef(data))
		end
	end
end

"""
    listen_to(source::AbstractSystem, listener::AbstractSystem)

This function make the system `listener` wait for data coming from the system `source`
"""
function listen_to(source::AbstractSystem, listener::AbstractSystem)

	## We will skip error checking on purpose
	# We are just fetching data so there should be not problem
	# We will just async this to ensure that we are still on the main thread
    push!(get_children(source), listener)
end

"""
    listen_to(ecs::ECSManager, archetype::NTuple{N,Symbol}, listener::AbstractSystem, num=1) where N

This function will make the system `listener` wait for data coming the `num` systems who have request the components `archetype`
"""
function listen_to(ecs::ECSManager, archetype::Tuple, listener::AbstractSystem, num=1)
	if haskey(ecs.systems, archetype)
		source = ecs.systems[archetype]

		(num == -1) && (num = length(source))
		for i = 1:num
		    listen_to(source[i], listener)
		end
	else
		@warn "There is no system matching the archetype $archetype yet."
	end
end

get_children(system::AbstractSystem) = getfield(system, :children)
