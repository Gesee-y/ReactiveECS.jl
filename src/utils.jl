##################################################################################################################
#####################################################   UTILS   ##################################################
##################################################################################################################

struct VirtualStructArray{T}
    data::StructArray{T}

    ## Constructor
    VirtualStructArray(s::StructArray{T}) where T = new{T}(s)
end
Base.getindex(v::VirtualStructArray, i) = getdata(v)[i]
Base.setindex!(v::VirtualStructArray, val, i) = getdata(v)[i] = val
getdata(v::VirtualStructArray) = getfield(v, :data)
Base.getproperty(v::VirtualStructArray, s::Symbol) = get_field(v, Val(s))

_print(f, io::IO, v::VirtualStructArray) = f(io, getfield(v, :data))

macro memoize(fun)
    name = fun.args[1].args[1]
    name isa Expr && (name = name.args[1])
    sub_name = Symbol("_"*string(name))
    dict_name = Symbol("DICT_"*string(name))
    eval(:(const $dict_name = Dict{Tuple, Any}()))
    if fun.args[1].args[1] isa Expr
        fun.args[1].args[1].args[1] = sub_name
    else
        fun.args[1].args[1] = sub_name
    end
    eval( quote
        $fun
        function $name(args...)
            if haskey($dict_name, args)
                return $dict_name[args]
            else
                v = $sub_name(args...)
                $dict_name[args] = v
                return v
            end
        end
    end
    )
end

function sleep_ns(t::Integer;sec=false)
	factor = sec ? 10 ^ 9 : 1
    t = UInt(t) * factor
    
    t1 = time_ns()
    while true
        if time_ns() - t1 >= t
            break
        end
        yield()
    end
end