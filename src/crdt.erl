-module(crdt).
-compile(export_all).

master_mnesia_subscribe(DbRecordName) -> 
    gen_server:call(crdt_gen, {mnesia_subscribe, DbRecordName}).

master_mnesia_unsubscribe(DbRecordName) -> 
    gen_server:call(crdt_gen, {mnesia_unsubscribe, DbRecordName}).

join(MasterNode) ->
    gen_server:call(crdt_gen, {join, MasterNode}).


merge(_DbRecordName,_Uuid,_Map) -> ok.
merge(_Style,_DbRecordName,_Uuid,_Map) -> ok.

get() -> ok.
get(_Uuid) -> ok.

update_subscribe() -> ok.
update_subscribe(_DbRecordName) -> ok.
update_subscribe(_DbRecordName,_Fields) -> ok.