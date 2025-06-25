################################################# Logging Module ################################################

using Dates

abstract type AbstractLogData end

@enum LogLevel begin
	TRACE
	DEBUG
	INFO
	WARNING
	ERROR
end

struct DefaultLogData end

struct LogEntry{T}
	timestamp::DateTime
	message::String
	level::LogLevel
	extra::T

	## Constructor

	LogEntry{T}(timestamp::DateTime,message::String,level::LogLevel,data=DefaultLogData()) where T <: AbstractLogData = new{T}(timestamp,message,level,data)
end

LogEntry(d::Dict) = LogEntry{Symbol(d["tag"])}(
	DateTime(d["timestamp"]),
	d["message"], 
	eval(Symbol(d["level"]))
	)

struct LogTracer
	name::Date
	start::Float64
	entries::Vector{LogEntry}
	commited::Vector{LogEntry}

	## Constructor

	LogTracer() = new(Dates.now(),time(),LogEntry[], LogEntry[])
end

#=
    @Notifyer ON_LOG(l::LogEntry)

This notifyer is emitted each time an entry is logged with Log!
=#
@Notifyer ON_LOG(l)

#=
    @Notifyer ON_LOG_WRITTEN(io::IO,l::LogEntry)

This Notifyer is emitted when a log a written in an IO
=#
@Notifyer ON_LOG_WRITTEN(io::IO,l)

macro logdata(ex)
	return quote 
		mutable struct $ex <: AbstractLogData
		    stats::NamedTuple

		    $ex() = new() 
	    end 
    end
end

macro profile(ex)
	if debug_mode()
		eval(quote @timed $ex end)
	else
		eval(ex)
	end
end


enable_value(ON_LOG)
enable_value(ON_LOG_WRITTEN)
async_notif(ON_LOG)
async_notif(ON_LOG_WRITTEN)

filter_level(level::LogLevel) = filter_log(l -> l.level == level)
filter_log(f::Function) = filter(f, ON_LOG)

"""
    debug_mode()

You can overload this method each time you wanna enable or disable log level
"""
debug_mode() = false
profile_mode() = false

get_name(T::Type{<:AbstractLogData}) = T
min_loglevel() = INFO
get_elapsed(logger::LogTracer) = time() - logger.start

include("operations.jl")