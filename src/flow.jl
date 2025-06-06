################################################# Data flow ####################################

export @system
export dispatch_data, listen_to

#=
    Let's start by making a simple thing. a flow is a channel, in which we put and take data
    Since taking and putting is kind of costly, we will batch them, meaning we send a bunch of data
    instead of individual data.
=#

const CHUNK_SIZE = 512

struct DataFlow{T}
	input::Channel{Vector{T}}
	output::Channel{Vector{T}}

    ## Constructors
	DataFlow{T}() where T = new{T}(Channel{Vector{T}}(Inf), Channel{Vector{T}}(Inf))
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

function dispatch_data(ecs, chunk_size=CHUNK_SIZE)
	skipped = 0
	while skipped < length(ecs.systems)
		skipped = 0
		for archetype in keys(ecs.systems)
			c = ecs.chunk_count
			s = 1 + chunk_size * (c-1)
			e = chunk_size * c
			data = ecs.groups[archetype]
			L = length(data)
			s > L && (skipped += 1; continue)
			e > L && (e = L)

			systems = ecs.systems[archetype]
			for system in systems
			    put!(system.flow.input, data[s:e])
			end
		end
	    ecs.chunk_count += 1
    end
	ecs.chunk_count = 1
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
