# ECSInterface.jl

An interface for any ECS implementation should overload to make it easier to use.

## API

### Types

```
AbstractECS, AbstractEntity, AbstractQuery
```

### component functions
```
add_components!, remove_components!, has_components, get_components, set_components!
get_all_components, exchange_components!
```

### entity functions
```
new_entity!, new_entities!, remove_entity!, remove_entities!
is_alive, is_zero, get_entities, entity_count
```

### resource functions
```
has_resource, get_resource, add_resource!, set_resource!, remove_resource!
```

### query functions
```
query
```

### system functions
```
reset!, register_system!, unregister_system!, run_systems!, get_systems
```

### event/hook functions
```
on_entity_created!, on_entity_destroyed!, on_component_added!, on_component_removed!
```