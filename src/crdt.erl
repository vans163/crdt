-module(crdt).
-compile(export_all).

master_mnesia_subscribe(DbRecordName) -> 
    gen_server:call(crdt_master_gen, {mnesia_subscribe, DbRecordName}).

master_mnesia_unsubscribe(DbRecordName) -> 
    gen_server:call(crdt_master_gen, {mnesia_unsubscribe, DbRecordName}).

join(MasterNode) ->
    gen_server:call(crdt_remote_gen, {join, MasterNode}).


merge(_DbRecordName,_Uuid,_Map) -> not_implemented.
merge(_Style,_DbRecordName,_Uuid,_Map) -> not_implemented.

get() -> 
    gen_server:call(crdt_remote_gen, get).
get(DbRecordName) -> 
    gen_server:call(crdt_remote_gen, {get, DbRecordName}).
get(DbRecordName, Uuid) -> 
    gen_server:call(crdt_remote_gen, {get, DbRecordName, Uuid}).

local_subscribe() ->
    gen_server:call(crdt_remote_gen, local_subscribe).
local_subscribe(DbRecordName) ->
    gen_server:call(crdt_remote_gen, {local_subscribe, DbRecordName}).
local_subscribe(DbRecordName, MapArgs) ->
    gen_server:call(crdt_remote_gen, {local_subscribe, DbRecordName, MapArgs}).
%local_subscribe(DbRecordName, Keys) ->
%    gen_server:call(crdt_remote_gen, {local_subscribe, DbRecordName, Keys}).
%local_subscribe(DbRecordName, Keys, Fields) ->
%    gen_server:call(crdt_remote_gen, {local_subscribe, DbRecordName, Keys, Fields}).




