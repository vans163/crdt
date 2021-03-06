-module(crdt_etc).
-compile(export_all).

-define(DELETE_KEY, <<"zxcye23_delete_4334de">>).
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
            Acc#{Key=> ?DELETE_KEY}
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

diff_map_delete(Map) -> diff_map_delete(Map, [], []).
diff_map_delete(Map, DList, KeyList) ->
    maps:fold(fun(K,V,{AMap, ADList})->
        if
            is_map(V) -> 
                {V2, ADList2} = diff_map_delete(V, ADList, KeyList++[K]),
                {AMap#{K=> V2}, ADList++ADList2};
            V == ?DELETE_KEY -> {maps:remove(K, AMap), ADList++([KeyList++[K]])};
            true -> {AMap, ADList}
        end
    end, {Map, DList}, Map).
    

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

merge_nested(Old, New) when is_map(Old), is_map(New) ->
    MergeMap = maps:fold(fun(KNew, VNew, Acc) ->
            case map:is_key(KNew, Old) of
                false -> Acc#{KNew=> VNew};
                true -> 
                    VOld = maps:get(KNew, Old),
                    if
                        VOld =:= VNew -> Acc;
                        is_map(VOld), is_map(VNew) -> 
                            Acc#{KNew=> merge_nested(VOld, VNew)};
                        true -> Acc#{KNew=> VNew}
                    end
            end
        end, #{}, New
    ),
    maps:merge(Old, MergeMap).

merge_nested2(Old, New) when is_map(Old), is_map(New) ->
    maps:fold(fun(KNew, VNew, Acc) ->
            VOld = maps:get(KNew, Old, 'undefined_zxc1253afzu673e980_does_not_exist'),
            if
                VOld =:= VNew -> Acc;
                is_map(VOld), is_map(VNew) -> 
                    Acc#{KNew=> merge_nested2(VOld, VNew)};
                true -> Acc#{KNew=> VNew}
            end
        end, Old, New
    ).

nested_delete(Map, DeleteList) when is_map(Map) ->
    nested_delete_1(Map, DeleteList).
nested_delete_1(Map, []) -> Map;
nested_delete_1(Map, [TermH|TermT]) ->
    DelKey = lists:last(TermH),
    Terms = lists:sublist(TermH, length(TermH)-1),
    Map2 = nested_delete_1_1(Map, DelKey, Terms),
    nested_delete_1(Map2, TermT).
nested_delete_1_1(Map, DelKey, []) -> 
    case maps:is_key(DelKey, Map) of
        true -> maps:remove(DelKey, Map);
        false -> Map
    end;
nested_delete_1_1(Map, DelKey, [HK|T]) ->
    case maps:is_key(HK, Map) of
        true -> Map#{HK=> nested_delete_1_1(maps:get(HK, Map), DelKey, T)};
        false -> Map
    end.
    


%nested_delete2(Map, DeleteList) when is_map(Map) ->
%    lists:foldl(fun
%        ([K1], A) ->
%            maps:remove(K1, A);

%        ([K1, K2], A) ->
%            V1 = maps:get(K1, A),
%            A#{K1=> maps:remove(K2, V1)};

%        ([K1, K2, K3], A) ->
%            V1 = maps:get(K1, A),
%            V2 = maps:get(K2, V1),
%            A#{K1=> V1#{K2=> maps:remove(K3, V2)}};

%        ([K1, K2, K3, K4], A) ->
%            V1 = maps:get(K1, A),
%            V2 = maps:get(K2, V1),
%            V3 = maps:get(K3, V2),
%            A#{K1=> V1#{K2=> V2#{K3=> maps:remove(K4, V3)}}};

%        ([K1, K2, K3, K4, K5], A) ->
%            V1 = maps:get(K1, A),
%            V2 = maps:get(K2, V1),
%            V3 = maps:get(K3, V2),
%            V4 = maps:get(K4, V3),
%            A#{K1=> V1#{K2=> V2#{K3=> V3#{K4=> maps:remove(K5, V4)}}}}
%        end, Map, DeleteList).