################################################# Data flow ####################################

#=
    Let's start by making a simple thing. a flow is a channel, in which we put and take data
    Since taking and putting is kind of costly, we will batch them, meaning we send a bunch of data
    instead of individual data.
=#

struct DataFlow{T}
	input::Channel{WeakRef}
	output::Channel{WeakRef}

    ## Constructors
	DataFlow{T}() where T = new{T}(Channel{WeakRef}(Inf), Channel{WeakRef}(Inf))
end

#=
    Next, each system should have a data flow, but we need custom systems so we will have a macro
=#

macro system(expr, type)
	return quote
		mutable struct $expr <: AbstractSystem
			active::Bool
			flow::DataFlow{$type}

			## Constructors

			$expr() = new(true,DataFlow{$type}())
		end
	end
end

function dispatch_data(ecs)
	for archetype in keys(ecs.systems)
		data = ecs.groups[archetype]
		systems = ecs.systems[archetype]

		for system in systems
		    put!(system.flow.input, WeakRef(data))
		end
	end
end

function listen_to(source::AbstractSystem, listener::AbstractSystem)

	## We will skip error checking on purpose
	# We are just fetching data so there should be not problem
	# We will just async this to ensure that we are still on the main thread
    listener.input = source.output
end

function listen_to(ecs::ECSManager, archetype::NTuple{N,Symbol}, listener::AbstractSystem) where N
	if haskey(ecs.systems, archetype)
		source = ecs.systems[archetype]
		listen_to(source, listener)
	else
		@warn "There is no system matching the archetype $archetype yet."
	end
end
