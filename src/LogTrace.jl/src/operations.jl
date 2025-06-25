################################################## Log Operations #######################################################

"""
    Log!(logger::LogTracer,tag::Symbol,type::LogLevel,msg::String)

This will log data into the logger object.
The Logs will be saved in RAM, if you want them in a file, you just call `write!`
"""
function Log!(logger::LogTracer,tag::T,type::LogLevel,msg::String) where T <: AbstractLogData
	if (type >= min_loglevel() || debug_mode())

		entry = LogEntry{T}(Dates.now(), msg, type, tag)
		push!(logger.entries, entry)

		ON_LOG.emit = entry
	end
end

function profile_start!(l::AbstractLogData)
    l.start = time_ns()
end
function profile_end!(l::AbstractLogData)
    l.end = time_ns()
    l.elapsed = l.end - l.start
end
function LogProfile!(logger::LogTracer,tag::T,type::LogLevel,msg::String) where T <: AbstractLogData
	if (type >= min_loglevel() || debug_mode())

		entry = LogEntry{T}(Dates.now(), msg, type, tag)
		push!(logger.entries, entry)

		ON_LOG.emit = entry
	end
end


"""
    write!(logger::LogTracer)

Write the log stored in RAM to the default `logger`'s file
"""
write!(logger::LogTracer) = write!("$(logger.name).log", logger)

"""
    write!(path::String, logger::LogTracer)

Write the logs stored in RAM to the file at `path`
"""
function write!(path::String, logger::LogTracer)
	# We first attempt to open the file to append to it
	try 
	    io = open(path, "a")
	    write!(io, logger)
	catch e

		# If the file doesnt exist
		# We try to create one
		try 
			io = open(path, "w")
			write!(io,logger)
		# If it still doen't work
		catch e
			error("Failed to write at file $path.\n Error $e")
		end
	end
end

"""
    write!(io::IO,logger::LogTracer)

Write the logs stored in RAM to `io`
"""
function write!(io::IO,logger::LogTracer)
	while !isempty(logger.entries)
		entry = popfirst!(logger.entries)
		push!(logger.commited, entry)
		write(io, entry)

		ON_LOG_WRITTEN.emit = entry
	end

	flush(io)
end



"""
    write(io::IO,l::LogEntry)

Write the log `l` to the IO `io
"""
Base.write(io::IO,l::LogEntry) = write(io, to_string(l))

Base.print(io::IO, l::LogEntry) = print(io, to_string(l))
Base.println(io::IO, l::LogEntry) = println(io, to_string(l))

"""
    to_string(l::LogEntry{S})

Convert a LogEntry into a readable string.
"""
to_string(l::LogEntry{S}) where S = """$(l.timestamp)\n[$(get_name(S))] $(l.level) : $(l.message)\n"""
to_dict(l::LogEntry{S}) where S = Dict(
        "timestamp" => l.timestamp,
        "level" => string(l.level),
        "tag" => string(S),
        "message" => l.message
    )

function to_json(l::LogEntry)
    return JSON.json(to_dict(l))
end

