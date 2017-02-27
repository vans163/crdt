-module(crdt_etc).
-compile(export_all).

delete_KEY() -> <<"zxcye23_delete_4334de">>.

merge(ListOfMaps) ->
    lists:foldl(fun(Map, Acc) ->
            maps:merge(Acc, Map)
        end, #{}, ListOfMaps
    ).

diff_map(Old, New) when Old =:= New -> #{};
diff_map(Old, New) when is_map(Old), is_map(New) == false -> New;
diff_map(Old, New) when is_map(Old) ->
    OldKeys = maps:keys(Old),
    NewKeys = maps:keys(New),

    OldMinusNew = OldKeys -- NewKeys,
    Map1 = lists:foldl(fun(Key, Acc) ->
            Acc#{Key=> delete_KEY()}
        end, #{}, OldMinusNew 
    ),

    NewMinusOld = NewKeys -- OldKeys,
    Map2 = lists:foldl(fun(Key, Acc) ->
            Acc#{Key=> maps:get(Key, New)}
        end, #{}, NewMinusOld 
    ),

    RemainingKeys = NewKeys -- NewMinusOld,
    Map3 = lists:foldl(fun(Key, Acc) ->
            OldVal = maps:get(Key, Old),
            NewVal = maps:get(Key, New),
            case OldVal =:= NewVal of
                true -> Acc;
                false ->
                    Acc#{ Key=> diff_map(OldVal, NewVal) }
            end
        end, #{}, RemainingKeys
    ),
    maps:merge(maps:merge(Map1, Map2), Map3);
diff_map(Old, New) when Old =/= New -> New.

nested_merge(Old, New) when is_map(Old), is_map(New) ->
    OldKeys = maps:keys(Old),
    NewKeys = maps:keys(New),

    NewMinusOld = NewKeys -- OldKeys,
    Map2 = lists:foldl(fun(Key, Acc) ->
            Acc#{Key=> maps:get(Key, New)}
        end, #{}, NewMinusOld 
    ),

    RemainingKeys = NewKeys -- NewMinusOld,
    Map3 = lists:foldl(fun(Key, Acc) ->
            OldVal = maps:get(Key, Old),
            NewVal = maps:get(Key, New),
            if
                OldVal =:= NewVal -> Acc;
                is_map(OldVal), is_map(NewVal) -> 
                    Acc#{Key=> nested_merge(OldVal, NewVal)};
                true -> Acc#{Key=> NewVal}
            end
        end, #{}, RemainingKeys
    ),
    Merge = maps:merge(Map2, Map3),
    maps:merge(Old, Merge).