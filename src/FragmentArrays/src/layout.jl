#############################################################################################################################################################################
######################################################################## DATA LAYOUT ########################################################################################
#############################################################################################################################################################################

########## Basic interface

Base.length(::T) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.push!(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.pushfirst!(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.append!(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.pop!(::T) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.resize!(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.insert!(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.getindex(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.setindex!(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.firstindex(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.lastindex(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")
Base.iterate(::T, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")

initialize_layout(::Type{T}, args...) where {T <: AbstractFragmentLayout} = error("Function not implemented for type $T.")

### Array Layout

Base.length(a::AbstractArrayLayout) = length(_getdata(a))
Base.push!(a::AbstractArrayLayout, args...) = push!(_getdata(a), args...)
Base.pushfirst!(a::AbstractArrayLayout, args...) = pushfirst!(_getdata(a), args...)
Base.append!(a::AbstractArrayLayout, args...) = append!(_getdata(a), args...)
Base.pop!(a::AbstractArrayLayout) = pop!(_getdata(a))
Base.insert!(a::AbstractArrayLayout, args...) = insert!(_getdata(a), args...)
Base.resize!(a::AbstractArrayLayout, args...) = resize!(_getdata(a), args...)
Base.getindex(a::AbstractArrayLayout, i::Integer) = getindex(_getdata(a), i)
Base.getindex(a::AbstractArrayLayout, r::UnitRange) = getindex(_getdata(a), r)
Base.setindex!(a::AbstractArrayLayout, args...) = setindex!(_getdata(a), args...)
Base.firstindex(a::AbstractArrayLayout) = firstindex(_getdata(a))
Base.lastindex(a::AbstractArrayLayout) = lastindex(_getdata(a))
Base.iterate(a::AbstractArrayLayout, args...) = iterate(_getdata(a), args...)

initialize_layout(::Type{T}, ::UndefInitializer, n) where {T <: AbstractArrayLayout} = T(undef, n)
initialize_layout(::Type{T}, args...) where {T <: AbstractArrayLayout} = T(args...)

_getdata(a::AbstractArrayLayout) = getfield(a, :data)