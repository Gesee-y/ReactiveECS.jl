include("..\\src\\LogTrace.jl")

@logdata Nobody
@logdata Render

ON_ERROR = filter_level(ERROR)

connect(ON_LOG) do l
    println(l)
end

connect(ON_ERROR) do l
    println("ERROR")
end

logger = LogTracer()

l = Log!(logger, Nobody(), INFO, "Everything is cool bro.")
l2 = Log!(logger, Render(), ERROR, "It may be dangerous here.")

path = "today.log"
write!(path, logger)

sleep(2)