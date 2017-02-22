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

Without crdt your flow might look like the following, the client presses a button to start the container, the webserver receives the api call and writes to the database that the containers power switch is on, the logic core in response to the database event of the power switch changing sends a cast to the worker node that the containers power switch changed, the worker node receives the cast and checks if the container is running already, if not the worker node starts the container, on success the worker node casts back to the logic core that the container was started, the logic core now writes to the database that the container was started, the webserver receives an event that the containers power is now on and forwards this to the client. Phew.

With full crdt your flow now looks like, the client presses a button to start the container, the container data model on the client end changes its power switch to on, the update propogates to the logic core which validates the power switch value, the worker node eventually receives an event that the power switch value was changed, the worker node starts the container, the worker node sets the power on the container to on, the client eventually receives confirmation that the container is powered on. Much better!
