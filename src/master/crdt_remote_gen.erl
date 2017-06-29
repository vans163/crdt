-module(crdt_remote_gen).
-behavior(gen_server).
-compile(export_all).

-import(crdt_etc, [delete_KEY/0, merge/1, diff_map/2, nested_merge/2, nested_delete/2]).

handle_cast(_, S) -> {noreply, S}.
code_change(_OldVersion, S, _Extra) -> {ok, S}. 
terminate(_R, _S) -> ok.

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    %process_flag(trap_exit, true),
    io:format("~p: Started!~n", [?MODULE]),
    LSEts = ets:new(remote_local_subscription_ets, [ordered_set, private]),
    catch ets:new(crdt_remote_config, [ordered_set, public, named_table]),

    erlang:send_after(500, self(), tick_push),
    {ok, #{state=> #{}, ls_ets=> LSEts, diff=> #{}, diff_delete=> #{}}}.


handle_call(join_remote, _, S) ->
    pg2:join(crdt, self()),
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

handle_call({local_subscribe, DbRecordName, MapArgs2}, {Pid, _}, S) when is_map(MapArgs2) -> 
    LSEts = maps:get(ls_ets, S),

    MapArgs = maps:merge(
        #{keys=> [], fields=> [], mutator=> undefined},
        MapArgs2),
    Keys = maps:get(keys, MapArgs),
    Fields = maps:get(fields, MapArgs),
    Mutator = maps:get(mutator, MapArgs),

    true = ets:insert(LSEts, {{Pid, DbRecordName}, MapArgs}),

    DbState2 = case Keys of
        [Key] ->
            #{Key=> maps:get(Key, maps:get(DbRecordName, maps:get(state, S), #{}), #{})};
        _ ->
            crdt_remote_gen:p_with_keys(Keys, maps:get(DbRecordName, maps:get(state, S), #{}))
    end,
    DbState3 = crdt_remote_gen:p_with_fields(Fields, DbState2),
    DbState4 = crdt_remote_gen:p_mutate(Mutator, DbState3),

    {reply, DbState4, S}.

%handle_call({local_subscribe, DbRecordName, Keys}, {Pid, _}, S) when is_list(Keys) -> 
%    LSEts = maps:get(ls_ets, S),
%    State = maps:get(state, S),
%    DbState = maps:get(DbRecordName, State, #{}),
%    DbState2 = p_with_keys(Keys, DbState),
%    true = ets:insert(LSEts, {{Pid, DbRecordName}, #{keys=> Keys}}),
%    {reply, DbState2, S};
%handle_call({local_subscribe, DbRecordName, Keys, Fields}, {Pid, _}, S) when is_list(Keys), is_list(Fields) -> 
%    LSEts = maps:get(ls_ets, S),
%    State = maps:get(state, S),
%    DbState = maps:get(DbRecordName, State, #{}),
%    DbState2 = p_with_keys(Keys, DbState),
%    DbState3 = p_with_diff(Fields, DbState2),
%    true = ets:insert(LSEts, {{Pid, DbRecordName}, #{keys=> Keys, fields=> Fields}}),
%    {reply, DbState3, S}.

p_with_keys([], Diff) -> Diff;
p_with_keys(Keys, Diff) when is_map(Diff) -> maps:with(Keys, Diff);
p_with_keys(Keys, DeleteList) when is_list(DeleteList) -> 
    lists:foldl(fun(Del=[H|_], A) ->
        case lists:member(H, Keys) of
            true -> A ++ [Del];
            false -> A
        end
    end, [], DeleteList).

p_with_fields([], Diff) -> Diff;
p_with_fields(Fields, Diff) when is_map(Diff) ->
    maps:fold(fun(K,V,A) ->
            With = maps:with(Fields, V),
            case erlang:map_size(With) of
                0 -> A;
                _ -> A#{K=> With}
            end
        end, #{}, Diff);
p_with_fields(Fields, DeleteList) when is_list(DeleteList) ->
    lists:foldl(fun
        (Del=[_,Field|_], A) ->
            case lists:member(Field, Fields) of
                true -> A ++ [Del];
                false -> A
            end;
        (_,A) -> A
    end, [], DeleteList).

p_mutate(undefined, Diff) -> Diff;
p_mutate({Mod, Fun, Args}, Diff) -> 
    erlang:apply(Mod, Fun, [Diff]++Args).

p_proc_local_subcribe(LSEts, Diff, DiffDelete) ->
    Subs = ets:tab2list(LSEts),
    Keys = sets:to_list(sets:from_list(
        maps:keys(Diff) ++ maps:keys(DiffDelete))),
    lists:foldl(fun
        ({{Pid, all}, _}, Cache) ->
            lists:foreach(fun(Key) ->
                TheDiff = maps:get(Key, Diff, #{}),
                TheDeleteList = maps:get(Key, DiffDelete, []),
                Pid ! {crdt_diff, Key, TheDiff, TheDeleteList}
            end, Keys),
            Cache;

        ({{Pid, DbRecordName}, 
            Q=#{keys:= QKeys, fields:= QFields, mutator:= QMutator}}, Cache) 
        ->
            lists:foldl(fun
                (Key, {CacheDiff2, CacheDelete2}) when Key =:= DbRecordName ->
                    Phash = erlang:phash2(Q),
                    {TheDiff, {CacheDiff33, CacheDelete33}} = case maps:get(Phash, CacheDiff2, undefined) of
                        DM when is_map(DM) -> 
                            {DM, {CacheDiff2, CacheDelete2}};

                        undefined ->
                            V = maps:get(Key, Diff, #{}),
                            V2 = p_with_keys(QKeys, V),
                            V3 = p_with_fields(QFields, V2),
                            V4 = p_mutate(QMutator, V3),
                            {V4, {maps:put(Phash, V4, CacheDiff2), CacheDelete2}}
                    end,
                    {TheDeleteList,Cache4} = case maps:get(Phash, CacheDelete2, undefined) of
                        DL when is_list(DL) ->
                            {DL, {CacheDiff33, CacheDelete33}};

                        undefined ->
                            VV = maps:get(Key, DiffDelete, []),
                            VV2 = p_with_keys(QKeys, VV),
                            VV3 = p_with_fields(QFields, VV2),
                            VV4 = p_mutate(QMutator, VV3),
                            {VV3, {CacheDiff33, maps:put(Phash, VV4, CacheDelete33)}}
                    end,
                    Pid ! {crdt_diff, Key, TheDiff, TheDeleteList},
                    Cache4;
                (_, Cache2) -> Cache2
            end, Cache, Keys);

        ({{Pid, DbRecordName}, _}, Cache) ->
            lists:foreach(fun
                (Key) when Key /= DbRecordName -> ignore;
                (Key) when Key =:= DbRecordName ->
                    TheDiff = maps:get(Key, Diff, #{}),
                    TheDeleteList = maps:get(Key, DiffDelete, []),
                    Pid ! {crdt_diff, Key, TheDiff, TheDeleteList}
            end, Keys),
            Cache;

        (_,Cache) -> Cache
    end, {#{}, #{}}, Subs).

handle_info(tick_push, S) ->
    LSEts = maps:get(ls_ets, S),
    Diff = maps:get(diff, S),
    DiffDelete = maps:get(diff_delete, S),

    p_proc_local_subcribe(LSEts, Diff, DiffDelete),

    erlang:send_after(500, self(), tick_push),
    {noreply, S#{diff=> #{}, diff_delete=> #{}}};

handle_info({crdt_remote_diff, DbRecordName, Diff}, S) ->
    %io:format("~p: Got crdt remote diff~n ~p~n ~p~n", [?MODULE, DbRecordName, Diff]),
    OldDiff = maps:get(diff, S),
    OldDiff2 = maps:get(DbRecordName, OldDiff, #{}),
    NewDiff2 = nested_merge(OldDiff2, Diff),
    NewDiff = maps:put(DbRecordName, NewDiff2, OldDiff),

    State = maps:get(state, S),
    DbRecord = maps:get(DbRecordName, State, #{}),
    DbRecord2 = nested_merge(DbRecord, Diff),
    StateNew = maps:put(DbRecordName, DbRecord2, State),
    {noreply, S#{state=> StateNew, diff=> NewDiff}};

handle_info({crdt_remote_diff_delete, DbRecordName, DeleteList}, S) ->
    %io:format("~p: Got crdt remote diff delete~n ~p~n ~p~n", [?MODULE, DbRecordName, DeleteList]),
    OldDiffDelete = maps:get(diff_delete, S),
    OldDiffDelete2 = maps:get(DbRecordName, OldDiffDelete, []),
    NewDiffDelete2 = sets:to_list(sets:from_list(OldDiffDelete2++DeleteList)),
    NewDiffDelete = maps:put(DbRecordName, NewDiffDelete2, OldDiffDelete),

    State = maps:get(state, S),
    DbRecord = maps:get(DbRecordName, State, #{}),
    DbRecord2 = nested_delete(DbRecord, DeleteList),
    StateNew = maps:put(DbRecordName, DbRecord2, State),
    {noreply, S#{state=> StateNew, diff_delete=> NewDiffDelete}}.