## Handling time with signals ##

export timer, throttle, sleep_ns, set_fps

function sleep_ns(t::Integer;sec=true)
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

function sleep_ns(t::Real;sec=true)
	factor = sec ? 10 ^ 9 : 1
    t = UInt(Float32(t)*10^9)

    t1 = time_ns()
    while true
        if time_ns() - t1 >= t
            break
        end
        yield()
    end
end

"""
	timer(t::Real;async=true)

Create a Notifyer that will notify after `t` seconds. If `async` is true, then the timer will run in parallel,
else it will run in the current process and then can be use to stop the process for `t` seconds even without wait.

# Example

```julia-repl

julia> begin # We wrap it in a begin block to avoid the timer end before we enter the next instruction.
			t = timer(2)
			t2 = timer(5)

			connect(t) do el
			   	println("What the ? I waited \$el seconds")
			end

			wait(t2)
			println("Glad that timer ended.")
	   end

```
"""
function timer(t::Real;async=true)
	notif = Notifyer("Timer",(Real,))
	sleep_func = t < 0.5 ? sleep : sleep_ns

	f = _ -> begin
		delta = @elapsed sleep_func(t)
		notif.emit = delta
	end

	if async errormonitor(Threads.@spawn f(1))
	else f(1)
	end

	return notif
end

"""
	throttle(frq)

Create a notification that is emitted every `frq` second.
if you want to set the number of time the Notifyer should be updated per second see `set_fps`

# Example

```julia-repl

julia> count = -1

julia> begin 
			throttler = throttle(1)

			@Signal TicTac(d::Real)

			connect(TicTac) do dt
				global count += 1
				count % 2 == 0 ? println("Tic \$dt") : println("Tac \$dt")
			end

			connect(throttler) do dt
				TicTac[] = dt
			end

			## You can create a timer to close the throttler here
			#  timer1 = timer(5)
			#  wait(timer1)
			## close(throttler)
	   end
"""
function throttle(frq=0.0166667)
	notif = Notifyer("Throttler",(Real,))
	
	sleep_func = frq > 0.5 ? sleep : sleep_ns

	function f(t)
		while !notif.closed[]
			d = @elapsed sleep_func(frq)
			notif.emit = d
		end
	end

	errormonitor(Threads.@spawn f(1))

	return notif
end

"""
	set_fps(f)

Create a notification that will be update `f` time per second. That notification emit the current frame per second,
the speed in percent and the elapsed time since the last notification.

# Example

```julia-repl

julia> begin
			timer2 = timer(5)
			fps_counter = set_fps(60)

			connect(fps_counter) do dt,fps,speed
				string_to_print = "\$fps FPS || Speed \$speed || delta = \$dt"
				println(string_to_print)
			end

			wait(timer2)
			close(fps_counter)
	   end
```
"""

function set_fps(f::Signed)
	rate = 1/f
	FPS = Notifyer("FPS",(Float64,Int,Float32))
	throttle_notif = throttle(rate)

	connect(throttle_notif) do dt
		current_fps = Int(ceil(1/dt))
		percent = Float32(current_fps*100/f)
		

		FPS.emit = (dt,current_fps,percent)
	end

	return FPS
end
