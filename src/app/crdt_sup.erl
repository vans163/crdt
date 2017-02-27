-module(crdt_sup).
-behaviour(supervisor).
-compile(export_all).

start_link() -> 
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok,
        {
            {one_for_one, 2, 10}, 
            [
                {crdt_gen, {crdt_gen, start_link, []}, permanent, 5000, worker, dynamic}
            ]
        }
    }.