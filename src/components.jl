##################################################################################################################
#################################################   COMPONENTS   #################################################
##################################################################################################################

export @component
export create_component, get_name, get_bits, is_composable, compose!

const BIT_INDEX = Ref(0)
const MAX_COMPONENT_NUM = 512
const BIT_VECTOR = BitType == BitVector ? BitVector(ntuple(i -> i == 1, MAX_COMPONENT_NUM)) : BitType(1)
const BIT_FUNC = () -> BIT_VECTOR >> BIT_INDEX[]
const COMPOSE_KEYWORD = :composable
const DIRTY_FIELD = :dirty

###################################################### Core ######################################################

"""
    @component name begin
        field1
        field2
          .
          .
          .
        fieldn
    end

This macro create a new component for you. It's possible to do it manually but there is no real gains
    @component composable name begin
        field1
        field2
          .
          .
          .
        fieldn
    end

This will create a new composable component.
This means that modifications on this component propagate to its children.
You should then define its `compose!` method like this

```julia

# `T` is your component type
function compose!(vs::VirtualStructArray{T}, parent_id, child_id) where T <: AbstractComponent
	# Your processing
	# Should set the new data of the child
end
```
"""
macro component(name, block)
	struct_name = Symbol(string(name)*_default_suffix())
	ex = string(name) # Just to interpolate a symbol
	
	# We add the dirty field
	pushfirst!(block.args, :($DIRTY_FIELD::Bool))
	
	## We add the constructor
	push!(block.args, :($struct_name(args...; dirty=true) = new(dirty, args...)))

	# Our struct expression
	struct_ex = Expr(:struct, false, :($struct_name <: AbstractComponent), block)
	eval(struct_ex)
	idx = BIT_INDEX[]

	BIT_INDEX[] += 1

    eval(quote
			create_component(::Type{$struct_name}, args...) = $struct_name(args...)
			export $struct_name
			get_name(::Type{$struct_name}) = Symbol($ex)
			get_bits(::Type{$struct_name}) = $BIT_VECTOR << $idx

			for field in fieldnames($struct_name)
				T = $struct_name
				f = field
				type = fieldtype(T, field)
				(get_field(st::VirtualStructArray{T},
					::Val{field})::Vector{type} = getproperty(getdata(st), (field))
				)
		    end
        end
    )
end

#=
macro component(compose, name, block)
	if compose === COMPOSE_KEYWORD
		struct_name = Symbol(string(name)*_default_suffix())
		ex = string(name) # Just to interpolate a symbol

		# We add the dirty field
		pushfirst!(block.args, :($DIRTY_FIELD::Bool))

		## We add the constructor
		push!(block.args, :($struct_name(args...; dirty=true) = new(dirty, args...)))

		# Our struct expression
		struct_ex = Expr(:struct, false, :($struct_name <: AbstractComponent), block)
		eval(struct_ex)
		idx = BIT_INDEX[]

		BIT_INDEX[] += 1

	    eval(quote
				create_component(::Type{$struct_name}, args...; dirty=true) = $struct_name(args..., dirty)
				export $struct_name
				RECS.get_name(::Type{$struct_name}) = Symbol($ex)
				RECS.get_bits(::Type{$struct_name}) = $BIT_VECTOR << $idx

				for field in fieldnames($struct_name)
					T = $struct_name
					f = field
					type = fieldtype(T, field)
					(RECS.get_field(st::VirtualStructArray{T},
						::Val{field})::Vector{type} = getproperty(getdata(st), (field))
					)
			    end
	        end
	    )
	else
		error("Invalid keyword $compose")
	end
end
=#

"""
    is_composable(::Type{T})
    is_composable(::T)

Returns true is the type `T` can be composed. This is similar to `is_mutable` 
"""
is_composable(::Type{T}) where T <: AbstractComponent = DIRTY_FIELD in fieldnames(T)
is_composable(::T) where T <: AbstractComponent = is_composable(T)

compose!(st::VirtualStructArray, p::Int, c::Int) = nothing

"""
    create_component(::Type{T}, args...) where T <:AbstractComponent

This function create a new component of type T with the given `args`.
If you are manually creating your components, you should overload this method with your own type.
"""
create_component(::Type{T}, args...) where T <:AbstractComponent = error("create_component is not defined for type $T")

"""
    get_name(::Type{T}) where T <: AbstractComponent

This function returns the name of a component as a string.
If you are manually creating your own component, you should overload this methods
But by default, it will be the name you gave to the struct.
"""
get_name(::T) where T <: AbstractComponent = get_name(T)
get_name(::Type{T}) where T <: AbstractComponent = Symbol(T.name.name)

"""
    get_field(v::VirtualStructArray, s)

This function return a typed field of a virtual struct array
"""
get_field(v::VirtualStructArray, s) = error("get_field not defined for $v")

"""
    get_bits(::AbstractComponent)

This function return the bit signature of a component as a bit vector. A component just represen one bit 
"""
get_bits(::T) where T <: AbstractComponent = get_bits(T)
get_bits(::Type{<:AbstractComponent}) = BitType == BitVector ? BitVector(()) : BitType(0)
get_bits(t::Union{Tuple, NamedTuple}) = get_bits(BitType, t)
function get_bits(::Type{BitVector}, t::Union{Tuple, NamedTuple})
    
	# We initialize the bit vector
	v::BitVector = get_bits(t[1])
	L = length(t)

	# Then we just add the other bit vector
	for i in 2:L
		elt = t[i]
		v += get_bits(elt)
	end

	return v
end
get_bits(::Type{<:Unsigned}, t::Union{Tuple, NamedTuple}) = sum(get_bits.(t))
get_bits(n::Integer) = UInt128(n)


"""
    default_suffix()

This function return the defaut suffix that will be added to your components.
You can overload this to customize the suffix and create manually you component.
The default value is `"Component"`.
"""
_default_suffix() = "Component"

match_archetype(b1::BitVector, b2::BitVector) = (b1 .& b2) == b2
match_archetype(b1::Unsigned, b2::Unsigned) = (b1 & b2) == b2
