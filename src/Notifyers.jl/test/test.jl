include("..\\src\\Notifyers.jl")

using .Notifyers

@Notifyer Test1
@Notifyer Test2(x::Int)

for i in 1:1000
	connect(Test1) do
		rand(50)
	end
end

async_notif(Test1)

@time Test1.emit
@time Test1.emit

sleep(1)