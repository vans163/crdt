-module(crdt_mnesia_subscriber_gen).
-behavior(gen_server).
-compile(export_all).

-import(crdt_etc, [delete_KEY/0, merge/1, diff_map/2, nested_merge/2]).

handle_cast(_, S) -> {noreply, S}.
code_change(_OldVersion, S, _Extra) -> {ok, S}. 
terminate(_R, _S) -> ok.

start_link(P) -> gen_server:start_link(?MODULE, P, []).

init({Parent, DbRecordName}) ->
    io:format("~p:~n Started ~p!~n", [?MODULE, DbRecordName]),

    {ok, _} = mnesia:subscribe({table, DbRecordName, detailed}),
    Rows = ets:tab2list(DbRecordName),
    Map = merge([#{Uuid=> State} || {_,Uuid,State}<-Rows]),

    erlang:send_after(200, self(), tick_push),

    {ok, #{
        dbrecordname=> DbRecordName, 
        parent=> Parent, 
        state=> Map, 
        diff=> #{}}}.

handle_call(state, _, S) -> 
    State = maps:get(state, S),
    {reply, State, S}.


handle_info(tick_push, S=#{diff:= Diff}) when 
erlang:map_size(Diff) > 0 
->
    Parent = maps:get(parent, S),
    DbRecordName = maps:get(dbrecordname, S),
    Diff = maps:get(diff, S),
    State = maps:get(state, S),
    StateNew = maps:merge(State, Diff),

    Parent ! {crdt_master_diff, DbRecordName, Diff},

    erlang:send_after(200, self(), tick_push),
    {noreply, S#{state=> StateNew, diff=> #{}}};
handle_info(tick_push, S) ->
    erlang:send_after(200, self(), tick_push),
    {noreply, S};

% -- Add
handle_info({mnesia_table_event, {write, _, {_, Uuid, State}, [], _}}, S) ->
    Diff = maps:get(diff, S),
    DiffNew = maps:put(Uuid, State, Diff),
    {noreply, S#{diff=> DiffNew}};

% -- Modify
handle_info({mnesia_table_event, {write, _, {_, Uuid, NewState}, [{_, Uuid, OldState}], _}}, S) ->
    Diff = maps:get(diff, S),
    DiffUuidMap = maps:get(Uuid, Diff),

    OldNewDiff = diff_map(OldState, NewState),
    DiffUuidMapNew = nested_merge(DiffUuidMap, OldNewDiff),
    DiffNew = maps:put(Uuid, DiffUuidMapNew, Diff),
    {noreply, S#{diff=> DiffNew}};

% -- Delete
handle_info({mnesia_table_event, {delete, _, _What, DeletedList, _}}, S) ->
    Diff = maps:get(diff, S),
    Uuids = [Uuid||{_,Uuid,_}<-DeletedList],
    DiffNew = lists:foldl(fun(Uuid, A) ->
            maps:put(Uuid, delete_KEY(), A)
        end, Diff, Uuids),
    {noreply, S#{diff=> DiffNew}}.