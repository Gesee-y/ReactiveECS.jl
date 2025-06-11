############################################# Helpers Functions ##############################################

export generate_id

generate_id() = time_ns()

get_component(entity::AbstractEntity, ::Type{T}) where T <: AbstractComponent = entity.components[get_name(T)]::T
get_component(entity::AbstractEntity, ::T) where T <: AbstractComponent = get_component(entity, T)

get_name(::Type{T}) where T <: AbstractComponent = Symbol(T.name.name)
get_name(::T) where T <: AbstractComponent = get_name(T)

get_type(T::Type) = T

get_bits(c::AbstractComponent) = get_bits(typeof(c))
get_bits(t::Vector{}) = begin
	res::UInt128 = 0
	for elt in t
		res += get_bits(elt)
	end

	return res
end
get_bits(::Type{T}) where T = 0b0
get_bits(n::Integer) = UInt128(n)

_match_archetype(entity::AbstractEntity, archetype::Tuple) = _match_archetype(entity, get_bits(archetype)) 
_match_archetype(entity::AbstractEntity, archetype::Unsigned) = (entity.archetype.value & archetype) == archetype
_match_archetype(entity::AbstractEntity, archetype::BitArchetype) = _match_archetype(entity, archetype.value)

function _remove_entity_in_groups(ecs::ECSManager, entity::AbstractEntity)
	for k in keys(ecs.groups)
		if _match_archetype(entity,k) && WeakRef(entity) in ecs.groups[k]
			filter!(x -> x.value !== entity, ecs.groups[k])
		end
	end
end

function _delete_tuple(t::NamedTuple, c::Symbol)
	f = findfirst(x -> x==c, keys(t))
	return NamedTuple{(keys(t[begin:f-1])...,keys(t[f+1:end])...)}((values(t[begin:f-1])..., values(t[f+1:end])))
end