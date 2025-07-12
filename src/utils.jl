##########################################################################################################################
########################################################   UTILS   #######################################################
##########################################################################################################################

export @memoize
export sleep_ns

"""
    @memoize function name(args...)
        # body
    end

This create a memoized version of the function.
This allow fast recomputations for function with deterministic result (the same args porduce the same results)
"""
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

"""
    sleep_ns(t::Integer;sec=false)

A microsecond resolution sleep, allowing more precise hold up that `sleep` which has millisecond resolution.
`sec` is wheter t is in seconds or nanoseconds.
"""
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