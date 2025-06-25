################ Test ###############

include("../src/Notifyers.jl")

using .Notifyers

@Notifyer Test1(x::Int,y::Int)

f(x::Int,y::Int) = x+y

c = 0
expensive_calc(x::Int,y::Int) = begin
	w = rand(10^5)
	#println("args are (",x,", ",y,")")
end

function main()
	#println(Test1)
	f(1,2)
	connect(expensive_calc,Test1)
	#connect(Test1) do x::Int,y::Int
	#	c :: Int = x+y
	#	println(c)
		#println(c)
	#end

	#println(Test1)

	sync_notif(Test1)
	async_latest(Test1,2)

	for i in 1:100
		Test1.emit = (i,1)
	end

	sleep(0.5)
	#Test1.emit = (1,1)

	#@time Test1.emit = (1,2)
	#@time Test1.emit = (1,2)
	sleep(1)
	for i in 1:100
		Test1.emit = (i,1)
	end
	sleep(1)
	async_latest(Test1,1)
	Test1.emit = (1,2)
	sleep(3)
	#println(get_state(Test1).async)
end

function main2()
	connect(expensive_calc,Test1)
	async_notif(Test1)
	async_all(Test1)

	for i in 1:100
		Test1.emit = (i,1)
	end

	sleep(0.5)
	reset(Test1)
	Test1.emit = (1,1)
	sleep(0.5)
end

function main3()
	#connect(expensive_calc,Test1)

	enable_value(Test1)
	sync_notif(Test1)
	#should_not_check_value(Test1)

	@time Test1[] = 1,1
	@time Test1[] = 1,1
	Test2 = map((x,y) -> x+y, Test1;typ=(Int,))
	Test3 = map((x,y) -> x*y, Test1;typ=(Int,))
	Test4 = map(+,Test2,Test3;typ=(Int,))

	@time Test1[] = 1,3
	@time Test1[] = 2,3

	println(Test4[])

end

main3()

