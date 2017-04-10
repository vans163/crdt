-module(crdt_remote_gen).
-behavior(gen_server).
-compile(export_all).

-import(crdt_etc, [delete_KEY/0, merge/1, diff_map/2, nested_merge/2, nested_delete/1]).

handle_cast(_, S) -> {noreply, S}.
code_change(_OldVersion, S, _Extra) -> {ok, S}. 
terminate(_R, _S) -> ok.

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    %process_flag(trap_exit, true),
    io:format("~p: Started!~n", [?MODULE]),
    LSEts = ets:new(remote_local_subscription_ets, [ordered_set, private]),
    catch ets:new(crdt_remote_config, [ordered_set, public, named_table]),

    {ok, #{state=> #{}, ls_ets=> LSEts}}.

handle_call({join, MasterNode}, _, S) ->
    ok = gen_server:call({crdt_master_gen, MasterNode}, join_rpc),
    {reply, ok, S};


handle_call(get, _, S) -> 
    State = maps:get(state, S),
    {reply, State, S};
handle_call({get, DbRecordName}, _, S) -> 
    State = maps:get(state, S),
    DbRecord = maps:get(DbRecordName, State, #{}),
    {reply, DbRecord, S};
handle_call({get, DbRecordName, Uuid}, _, S) -> 
    State = maps:get(state, S),
    DbRecord = maps:get(DbRecordName, State, #{}),
    DbRecordUuid = maps:get(Uuid, DbRecord, #{}),
    {reply, DbRecordUuid, S};


handle_call(local_subscribe, {Pid, _}, S) -> 
    LSEts = maps:get(ls_ets, S),
    State = maps:get(state, S),
    true = ets:insert(LSEts, {{Pid, all}, #{}}),
    {reply, State, S};
handle_call({local_subscribe, DbRecordName}, {Pid, _}, S) -> 
    LSEts = maps:get(ls_ets, S),
    State = maps:get(state, S),
    DbState = maps:get(DbRecordName, State, #{}),
    true = ets:insert(LSEts, {{Pid, DbRecordName}, #{}}),
    {reply, DbState, S};
handle_call({local_subscribe, DbRecordName, Keys}, {Pid, _}, S) when is_list(Keys) -> 
    LSEts = maps:get(ls_ets, S),
    State = maps:get(state, S),
    DbState = maps:get(DbRecordName, State, #{}),
    DbState2 = p_with_keys(Keys, DbState),
    true = ets:insert(LSEts, {{Pid, DbRecordName}, #{keys=> Keys}}),
    {reply, DbState2, S};
handle_call({local_subscribe, DbRecordName, Keys, Fields}, {Pid, _}, S) when is_list(Keys), is_list(Fields) -> 
    LSEts = maps:get(ls_ets, S),
    State = maps:get(state, S),
    DbState = maps:get(DbRecordName, State, #{}),
    DbState2 = p_with_keys(Keys, DbState),
    DbState3 = p_with_diff(Fields, DbState2),
    true = ets:insert(LSEts, {{Pid, DbRecordName}, #{keys=> Keys, fields=> Fields}}),
    {reply, DbState3, S}.

p_with_keys(Keys, Diff) -> maps:with(Keys, Diff).

p_with_diff(Fields, Diff) ->
    maps:fold(fun(K,V,A) ->
        With = maps:with(Fields, V),
            case erlang:map_size(With) of
                0 -> A;
                _ -> A#{K=> With}
            end
        end, #{}, Diff).

p_proc_local_subcribe(LSEts, DbRecordName, Diff) ->
    Subs = ets:tab2list(LSEts),
    lists:foreach(fun
        ({{Pid, all}, _}) ->
            Pid ! {crdt_diff, DbRecordName, Diff};

        ({{Pid, DbRecordName2}, #{keys:= Keys}}) when DbRecordName2 =:= DbRecordName ->
            case p_with_keys(Keys, Diff) of
                Diff2 when erlang:map_size(Diff2) =:= 0 -> ignore;
                Diff2 -> Pid ! {crdt_diff, DbRecordName, Diff2}
            end;

        ({{Pid, DbRecordName2}, #{keys:= Keys, fields:= Fields}}) when DbRecordName2 =:= DbRecordName ->
            Diff2 = p_with_keys(Keys, Diff),
            Diff3 = p_with_diff(Fields, Diff2),
            case Diff3 of
                Diff4 when erlang:map_size(Diff4) =:= 0 -> ignore;
                Diff4 -> Pid ! {crdt_diff, DbRecordName, Diff4}
            end;

        ({{Pid, DbRecordName2}, _}) when DbRecordName2 =:= DbRecordName ->
            Pid ! {crdt_diff, DbRecordName, Diff};

        (_) -> ignore
    end, Subs).


handle_info({crdt_remote_diff, DbRecordName, Diff}, S) ->
    %io:format("~p: Got crdt remote diff~n ~p~n ~p~n", [?MODULE, DbRecordName, Diff]),
    LSEts = maps:get(ls_ets, S),
    State = maps:get(state, S),
    DbRecord = maps:get(DbRecordName, State, #{}),
    DbRecord2 = nested_merge(DbRecord, Diff),
    DbRecord3 = nested_delete(DbRecord2),

    p_proc_local_subcribe(LSEts, DbRecordName, Diff),

    StateNew = maps:put(DbRecordName, DbRecord3, State),
    {noreply, S#{state=> StateNew}}.
