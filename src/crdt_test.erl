-module(crdt_test).
-compile(export_all).

-record(db_test, {uuid, data=#{}}).

write_1() ->
    mnesia:dirty_write({db_test, <<"sss-sss-aaa-aaa">>, 
        #{test=> #{another=> 5}, test2=> #{best=> #{bb=> <<"feae">>}}}}).

write_2() ->
    mnesia:dirty_write({db_test, <<"sss-sss-aaa-aaa">>, 
        #{test2=> #{best=> #{bb=> <<"azzzfeae">>}}}}).

recv() ->
    receive 
        {crdt_diff, db_test, Diff, DeleteList} ->
            io:format("~p ~p ~n", [Diff, DeleteList])
    after 100 -> ignore
    end.

start_master() ->
    application:ensure_all_started(crdt),
    crdt:master(),

    mnesia:create_schema([node()]),
    application:ensure_all_started(mnesia),

    mnesia:create_table(db_test, [
        {disc_copies, [node()]},
        {attributes, record_info(fields, db_test)}, 
        {type, ordered_set}
    ]),
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    mnesia:dirty_write({db_test, <<"sss-sss-aaa-aaa">>, 
        #{test=> #{another=> 5}, test2=> #{best=> #{bb=> <<"feae">>}}}}),

    crdt:master_mnesia_subscribe(db_test).

start_remote() ->
    application:ensure_all_started(crdt),
    crdt:remote_subscribe(),

    %_FullStateMap = crdt:local_subscribe().
    _PartialDbTestStateMap = crdt:local_subscribe(db_test, #{
        keys=> [<<"sss-sss-aaa-aaa">>], 
        fields=> [test2]
     %   mutator=> {__MODULE__, crdt_mutate_test, [UserUuid, Arg2]}
    }).