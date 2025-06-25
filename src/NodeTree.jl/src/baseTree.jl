## Implementing the tree system for the base objects ##

@noinline get_children(A::AbstractArray) = A

@noinline get_children(T::Tuple) = T

get_children(u::AbstractUnitRange) = Tuple(u)

get_children(ex::Expr) = ex.args

get_children(p::Pair) = (p.first,p.last)

get_children(d::AbstractDict) = pairs(d)

get_children(n) = ()