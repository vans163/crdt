-module(crdt_gen).
-behavior(gen_server).
-compile(export_all).

%-import(crdt_mnesia_subscriber_gen, [spawn_link/1]).

handle_cast(_, S) -> {noreply, S}.
code_change(_OldVersion, S, _Extra) -> {ok, S}. 
terminate(_R, _S) -> ok.

start_link() -> gen_server:start_link(?MODULE, [], []).

init([]) ->
    process_flag(trap_exit, true),
    io:format("~p: Started!~n", [?MODULE]),
    MEts = ets:new(mnesia_subscription_ets, [ordered_set, public, named_table]),
    REts = ets:new(remote_subscription_ets, [ordered_set, public, named_table]),
    {ok, #{ms_ets=> MEts, rs_ets=> REts}}.


p_mnesia_subscribe(DbRecordName, Ets) ->
    case ets:lookup(Ets, DbRecordName) of
        [] -> 
            {ok, Pid} = crdt_mnesia_subscriber_gen:spawn_link({self(), DbRecordName}),
            true = ets:insert(Ets, {DbRecordName, #{pid=> Pid}});
        _ -> ignore
    end.
p_mnesia_unsubscribe(DbRecordName, Ets) ->
    case ets:lookup(Ets, DbRecordName) of
        [] -> ignore;
        [{DbRecordName, #{pid:= SubPid}}] ->
            exit(SubPid, mnesia_unsubscribe),
            true = ets:delete(Ets, DbRecordName)
    end.

p_remote_subscribe(Pid, Ets) ->
    Node = erlang:node(Pid),
    case ets:lookup(Ets, Node) of
        [] ->
            _Ref = erlang:monitor(process, Pid), 
            true = ets:insert(Ets, {Node, #{pid=> Pid}});
        _ -> ignore
    end.
p_remote_unsubscribe(Pid, Ets) ->
    Node = erlang:node(Pid),
    ets:delete(Ets, Node).


handle_call({mnesia_subscribe, DbRecordName}, _, S) ->
    Ets = maps:get(ms_ets, S),
    p_mnesia_subscribe(DbRecordName, Ets),
    {reply, ok, S};
handle_call({mnesia_unsubscribe, DbRecordName}, _, S) ->
    Ets = maps:get(ms_ets, S),
    p_mnesia_unsubscribe(DbRecordName, Ets),
    {reply, ok, S};


handle_call({join, MasterNode}, _, S) ->
    ok = gen_server:call({?MODULE, MasterNode}, join_rpc),
    {reply, ok, S};
handle_call(join_rpc, SubscriberPid, S) ->
    Ets = maps:get(rs_ets, S),
    p_remote_subscribe(SubscriberPid, Ets),
    {reply, ok, S}.



handle_info({'DOWN', _Ref, process, Pid, Reason}, S) ->
    io:format("~p:~n DOWN because~n ~p~n", [?MODULE, Reason]),
    Ets = maps:get(rs_ets, S),
    p_remote_unsubscribe(Pid, Ets),
    {noreply, S};

handle_info({'EXIT', Pid, Reason}, S) ->
    Ets = maps:get(ms_ets, S),
    case ets:match_object(Ets, {'_', #{pid=> Pid}}) of
        [{DbRecordName,_}] ->
            io:format("~p:~n EXIT Mnesia Subscriber because~n ~p~n", [?MODULE, Reason]),
            timer:sleep(5000),
            p_mnesia_unsubscribe(DbRecordName, Ets),
            p_mnesia_subscribe(DbRecordName, Ets),
            {noreply, S};

        [] ->
            io:format("~p:~n EXIT because~n ~p~n", [?MODULE, Reason]),
            {stop, {shutdown, on_exit}, S}
    end;


handle_info({crdt_master_diff, DbRecordName, Diff}, S) ->
    io:format("~p: Got crdt diff~n ~p~n ~p~n", [?MODULE, DbRecordName, Diff]),
    {noreply, S}.


