-module(reddit_server).
-behaviour(gen_server).
-export([start_link/0,request/4,init/1,handle_call/3,handle_cast/2,handle_info/2]).
start_link() -> gen_server:start_link({local,?MODULE},?MODULE,[],[]).
-spec request(node() | pid(),binary(),reddit_engine:operation(),timeout()) -> {ok,term()} | {error,atom()}.
request(Server,User,Operation,Timeout) ->
  Address=case is_pid(Server) of true->Server; false->{?MODULE,Server} end,
  try gen_server:call(Address,{request,User,Operation},Timeout)
  catch exit:{timeout,_}->{error,timeout}; exit:{noproc,_}->{error,unavailable};
        exit:{{nodedown,_},_}->{error,unavailable}; exit:{nodedown,_}->{error,unavailable}
  end.
init([]) -> {ok,reddit_engine:new(application:get_env(reddit,mode,base))}.
handle_call({request,U,Op},_,S) ->
  {Next,Response}=reddit_engine:apply(S,U,Op), {reply,Response,Next};
handle_call(_,_,S) -> {reply,{error,invalid},S}.
handle_cast(_,S) -> {noreply,S}.
handle_info(_,S) -> {noreply,S}.
