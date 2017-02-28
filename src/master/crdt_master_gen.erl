-module(crdt_master_gen).
-behavior(gen_server).
-compile(export_all).

%-import(crdt_mnesia_subscriber_gen, [start_link/1]).

handle_cast(_, S) -> {noreply, S}.
code_change(_OldVersion, S, _Extra) -> {ok, S}. 
terminate(_R, _S) -> ok.

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    process_flag(trap_exit, true),
    io:format("~p: Started!~n", [?MODULE]),
    MEts = ets:new(mnesia_subscription_ets, [ordered_set, private]),
    REts = ets:new(remote_subscription_ets, [ordered_set, private]),
    catch ets:new(crdt_master_config, [ordered_set, public, named_table]),

    {ok, #{ms_ets=> MEts, rs_ets=> REts}}.


p_mnesia_subscribe(DbRecordName, Ets) ->
    case ets:lookup(Ets, DbRecordName) of
        [] -> 
            {ok, Pid} = crdt_mnesia_subscriber_gen:start_link({self(), DbRecordName}),
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

p_remote_send_base_state(RemotePid, MEts) ->
    MSubs = ets:tab2list(MEts),
    MPids = [MPid||{_,#{pid:=MPid}}<-MSubs],
    lists:foreach(fun(MPid) -> 
        {DbRecordName, State} = gen_server:call(MPid, state),
        RemotePid ! {crdt_remote_diff, DbRecordName, State}
    end, MPids).

p_remote_subscribe(RemotePid, MEts, REts) ->
    Node = erlang:node(RemotePid),
    case ets:lookup(REts, Node) of
        [] ->
            p_remote_send_base_state(RemotePid, MEts),
            _Ref = erlang:monitor(process, RemotePid), 
            true = ets:insert(REts, {Node, #{pid=> RemotePid}});
        _ -> ignore
    end.
p_remote_unsubscribe(RemotePid, Ets) ->
    Node = erlang:node(RemotePid),
    ets:delete(Ets, Node).


p_remote_broadcast(Pids, DbRecordName, Diff) ->
    lists:foreach(fun(Pid) -> 
        Pid ! {crdt_remote_diff, DbRecordName, Diff}
    end, Pids). 


handle_call({mnesia_subscribe, DbRecordName}, _, S) ->
    Ets = maps:get(ms_ets, S),
    p_mnesia_subscribe(DbRecordName, Ets),
    {reply, ok, S};
handle_call({mnesia_unsubscribe, DbRecordName}, _, S) ->
    Ets = maps:get(ms_ets, S),
    p_mnesia_unsubscribe(DbRecordName, Ets),
    {reply, ok, S};


handle_call(join_rpc, {SubscriberPid, _}, S) ->
    MEts = maps:get(ms_ets, S),
    REts = maps:get(rs_ets, S),
    p_remote_subscribe(SubscriberPid, MEts, REts),
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
    %io:format("~p: Got crdt master diff~n ~p~n ~p~n", [?MODULE, DbRecordName, Diff]),
    Ets = maps:get(rs_ets, S),
    RemoteSubs = ets:tab2list(Ets),
    %io:format("~p: remote subs ~p~n", [?MODULE, RemoteSubs]),
    Pids = [Pid||{_,#{pid:=Pid}}<-RemoteSubs],

    lists:foreach(fun(Pid) -> 
        Pid ! {crdt_remote_diff, DbRecordName, Diff}
    end, Pids),

    {noreply, S}.
