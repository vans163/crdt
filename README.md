# crdt
A simple CRDT written in Erlang

<img src="https://www.highstreet.io/wp-content/uploads/2014/12/sync.gif"/>


## Premise

crdt is being written to solve a serious problem in distributed systems.  Consider the case of a distributed system with medium complexity, you have a persistent data store with worker nodes.  The worker nodes must ensure a certain state is met based on the underlying data.  Currently your only option is to use a canundrum of message passing, calling and casting in order to get your data to the worker nodes then backwards to be persisted.  

To present a simple example say you have a distributed system with the following components, a forward facing webserver, a database, a logic core, many physical worker nodes which host many more virtual containers.

The webserver is responsible for taking input from the client, create|start|stop|restart container, as well as presenting output such as the current status of the containers belonging to the client.

The database is responsible for persisting the data as well as providing events and queries to give output.

The logic core is responsible for determining which worker node has free space to launch the container in.

The worker node is responsible for managing the state of the containers which are external to the erlang runtime and thus present external unreliability.

Without crdt your flow might look like the following, the client presses a button to start the container, the webserver receives the api call and writes to the database that the containers power switch is on, the logic core in response to the database event of the power switch changing sends a cast to the worker node that the containers power switch changed, the worker node receives the cast and checks if the container is running already, if not the worker node starts the container, on success the worker node casts back to the logic core that the container was started, the logic core now writes to the database that the container was started, the webserver receives an event that the containers power is now on and forwards this to the client. If the worker node takes too long or crashes during this processes the next two paragraphs that I have ommited would have been responsible for handling the logic of the netsplit.

*ommited*
  
*ommited*  
  
Phew.  
  
With crdt your flow now looks like, the client presses a button to start the container, the container data model on the client end changes its power switch to on, the update propogates to the logic core which validates the power switch value, the worker node eventually receives an event that the power switch value was changed, the worker node eventually starts the container, the worker node sets the power to on for the container, the client eventually receives confirmation that the container is powered on. Much better!

## Assumptions

To keep crdt simple we must make some assumptions.  
  - schema-lessness with support for validation
    - schemas in distributed systems cannot know the schema on a different codebase
    - validation at the logic nodes ensures our data is not tainted, as well as enforcing type safety
  - the core data structure is a map
    - no records, see above
    - maps can easily be supported everywhere
  - the core data structure is keyed
    - the final data structure as a record would be {db_container, term(), map()}
  - two operations
    - merge, to apply changes to the core data
    - get, to get the core data
  - a master logic node
    - responsible to validate the crdt merges
    - responsible to syncronize with the persistent database
    - currently waiting for R20 distributed erlang changes
    - no idea how to implement node pooling right now
    - the above will be removed time come

## Usage
### merge/3, merge/4
merge/3 eventually replicates the changes. It is asyncronous.  
If validation on the logic core fails the changes are ignored.  
```erlang
crdt:merge(db_container, Uuid, #{power=> true});
```   
merge/4 validate, is the same as merge/3 except it syncronously validates the data.  
It returns error or ok depending on validation success.  
```erlang
{error, {validate, power}} =
crdt:merge(validate, db_container, Uuid, #{power=> on});
```   
merge/4 perfect, is the same as merge/4 except it provides perfect consistency.  
NOTE: This is not implemented yet and maybe never will be.
```erlang
crdt:merge(perfect, db_container, Uuid, #{power=> true});
crdt:merge({perfect, 10000}, db_container, Uuid, #{power=> true});
```   
### get/2
Get the map data structure of the row as it is currently available on the local node.
```erlang
crdt:get(db_container, Uuid);
```   
