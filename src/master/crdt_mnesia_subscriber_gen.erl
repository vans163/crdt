-module(crdt_mnesia_subscriber_gen).
-behavior(gen_server).
-compile(export_all).

-import(crdt_etc, [delete_KEY/0, merge/1, diff_map/2, diff_map_delete/1, nested_merge/2, nested_delete/2]).

handle_cast(_, S) -> {noreply, S}.
code_change(_OldVersion, S, _Extra) -> {ok, S}. 
terminate(_R, _S) -> ok.

start_link(P) -> gen_server:start_link(?MODULE, P, []).

init({Parent, DbRecordName}) ->
    io:format("~p: Started ~p!~n", [?MODULE, DbRecordName]),

    {ok, _} = mnesia:subscribe({table, DbRecordName, detailed}),
    Rows = ets:tab2list(DbRecordName),
    Map = merge([#{Uuid=> State} || {_,Uuid,State}<-Rows]),
    erlang:send_after(200, self(), tick_push),

    {ok, #{
        dbrecordname=> DbRecordName, 
        parent=> Parent, 
        data=> Map, 
        diff=> #{},
        diff_delete=> []
        }}.

handle_call(data, _, S) -> 
    DbRecordName = maps:get(dbrecordname, S),
    Data = maps:get(data, S),
    {reply, {DbRecordName, Data}, S}.


handle_info(tick_push, S) ->
    Parent = maps:get(parent, S),
    DbRecordName = maps:get(dbrecordname, S),
    Diff = maps:get(diff, S),
    DeleteList = maps:get(diff_delete, S),
    Data = maps:get(data, S),

    HasDiff = (erlang:map_size(Diff) > 0) or (length(DeleteList) > 0),
    Data3 = case HasDiff of
        false -> Data;
        true ->
            Parent ! {crdt_master_diff, DbRecordName, Diff, DeleteList},
            Data2 = nested_merge(Data, Diff),
            nested_delete(Data2, DeleteList)
    end,

    erlang:send_after(200, self(), tick_push),
    {noreply, S#{data=> Data3, diff=> #{}, diff_delete=> []}};

% -- Add
handle_info({mnesia_table_event, {write, _, {_, Uuid, State}, [], _}}, S) ->
    Diff = maps:get(diff, S),
    DiffNew = maps:put(Uuid, State, Diff),
    {noreply, S#{diff=> DiffNew}};

% -- Modify
handle_info({mnesia_table_event, {write, _, {_, Uuid, NewState}, [{_, Uuid, OldState}], _}}, S) ->
    case diff_map(OldState, NewState) of
        OldNewDiff when erlang:map_size(OldNewDiff) =:= 0 ->
            {noreply, S};

        OldNewDiff ->
            Diff = maps:get(diff, S),
            DiffDelete = maps:get(diff_delete, S),

            {OldNewDiffDeleted, DeleteList2} = crdt_etc:diff_map_delete(OldNewDiff),
            DeleteList = [[Uuid]++X||X<-DeleteList2],
            DiffDeleteNew = sets:to_list(sets:from_list(DiffDelete++DeleteList)),

            DiffUuidMap = maps:get(Uuid, Diff, #{}),
            DiffUuidMapNew = nested_merge(DiffUuidMap, OldNewDiffDeleted),
            DiffNew = maps:put(Uuid, DiffUuidMapNew, Diff),

            {noreply, S#{diff=> DiffNew, diff_delete=> DiffDeleteNew}}
    end;

% -- Delete
handle_info({mnesia_table_event, {delete, _, _What, DeletedList, _}}, S) ->
    DiffDelete = maps:get(diff_delete, S),
    Uuids = [[Uuid]||{_,Uuid,_}<-DeletedList],
    DiffDelete2 = sets:to_list(sets:from_list(DiffDelete++Uuids)),
    {noreply, S#{diff_delete=> DiffDelete2}}.