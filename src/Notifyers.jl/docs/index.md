# Notifyers

So there you are to know more about the Notifyer package, we will start with the basis
creating a `Notifyer`.

Notifyer are structures used to call function(`Listeners`) on change.
Notifyer can be constructed:

   * Manually via : 
   `Notifyer(name::String,args::Tuple=(); state = StateData())` where `name` is the name of the notifyer, `args` is a tuple of type(or values that will be considered as default values) that will be use as signature for the Notifyer. `state` is the state object the notifyer should start with.
   e.g:

```julia
julia> using Notifyer # If you have not already import the package

julia> notif = Notifyer("A cool name", (Int,))
Notifyer with 0 listeners. Open = true :

julia>
```

   * Automatically via:
   `@Notifyer Notifyer_name(args)`. an example talks more than anything for this one
   `@Notifiyer Testing()`, `@Notifiyer Testing2(x::Int,y::Float64)`, 
   `@Notifiyer Testing3(x::Int,z=0)`. The variable name `x`, `y` or `z` are just there for intuitiveness but are mandatory.

   **Note** :
   		Notifyer created via the macro syntax will be created as constant in the global scope. the name of the constant is the same as the Notifyer name.

Once the Notifyer created, You have to know one thing: Notifyer's manipulation is mainly done via states.

## States

States determine how the Notifyer will react in different condition.
For example the function `sync_notif(n::Notifyer)` will set the notifyer to a synchronous state like in the Observable package (by default, Notifyer are in the asynchronous state like in Reactive.). 

The 2 main states are `ValueState` and `EmitState`. `ValueState` is a state in which the notifyer will keep track of the last value he receive, In `EmitState` mode, the notifyer will just emit value without keeping them (So, he only call the listener with some value that you indicate to it.). By default, a newly created `Notifyer` is in `EmitState`.

Let's see an example

```julia
using Notifyers

@Notifyer Notif(v::Int) # We create the notifyer

# We connect a function to the notifyer via connect(f::Function,n::Notifyer)
connect(Notif) do v
	println("We receive $v.")
end

# We emit a value.
Notif.emit = 4
```

We will explain everything
   * `using Notifyers` : First we import the Notifyers package (nothing new there)

   * `@Notifyer Notif(v::Int)` : We create a new notifyer with the macro syntax (meaning that `Notif` is now a constant in the global scope), We specify that the notifyer should accept a `Int`.

```julia
connect(Notif) do v
	println("We receive $v.")
end
```

Here we connect to the Notifyer `Notif` a function that will be called everytime Notif emit a value.
	The full syntax of connect is `connect(f::Function,notif::Notifyer;consume=false)`
	where `consume` indicate if the functiom should be disconnected from the Notifyer after the first emission. this function return a `Listener`

   * `Notif.emit = 4` this will call all the function who are listening to Notif with the data `4`, since `Notifyer`s are by default in the emit state, this is the correct syntax to emit the notification. Here is the same example but in the value state.

```julia
using Notifyers

@Notifyer Notif(v::Int) # We create the notifyer

# We connect a function to the notifyer via connect(f::Function,n::Notifyer)
connect(Notif) do v
	println("We receive $v.")
end

# We active the value state
enable_value(Notif)

# We emit a value.
Notif[] = 4
```

To go back to EmitState, use `disable_value(n::Notifyer)`

You can set a Notifyer to the synchronous state with
```julia
sync_notif(n::Notifyer)
```
In this state you can use the following functions
```julia
enable_consume(n::Notifyer) # Let the Notifyer remove consume listeners
disable_consume(n::Notifyer)
```

You can set a Notifyer to the asynchronous state with
```julia
async_notif(n::Notifyer)
```
Then you can use the following functions

### single_task
```julia
single_task(n::Notifyer) # Will tell if the notifyer should call all the listeners in a
# single task meaning they will be call one after another
```

### multiple_task
```julia
multiple_task(n::Notifyer) # Will tell the notifyer to create a task for every listener so
#they will be called in parallel
```

## Multi task state functions

### wait_all_callback
```julia
wait_all_callback(n::Notifyer) # Will tell the notifyer to wait for all the listener's task
#to execute before the current process can continue

```

### no_wait
```julia
no_wait(n::Notifyer) # Will tell the notifyer to not wait for all the task to finish.
```

## General functions

No matter that you are in synchronous or asynchronous state, these function will still be available

### set_delay
```julia
set_delay(n::Notifyer,d::Real) # Will create a delay between every listener call, only work
#in synchronous state or asynchronous state in single task state
```

### no_delay
```julia
no_delay(n::Notifyer) # Will tell the notifyer to not create a delay between listener calls.
```

### delay_first
```julia
delay_first(n::Notifyer) # Will tell the notifyer to create a delay before the first
#listener call
```

### async_all
```julia
async_all(n::Notifyer) # Will tell the notifyer to execute all his emission.
```

### async_oldest
```julia
async_oldest(n::Notifyer,cnt=1) # Will tell the notifyer to execute only `cnt` first
#emission, and to reject the other while those one are executing.
```

### async_latest
```julia
async_latest(n::Notifyer,cnt=1) # Will tell the notifyer to execute only `cnt` last
#emission, meaning that, if there is many emission in the notifyer channel, it will only
#execute the `cnt` last one.
```
