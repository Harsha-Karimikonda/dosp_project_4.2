-module(reddit_sup).
-behaviour(supervisor).
-export([start_link/0,init/1]).
start_link() -> supervisor:start_link({local,?MODULE},?MODULE,[]).
init([]) ->
  %% Restarting the in-memory engine resets data; a benchmark treats this as failure.
  {ok,{#{strategy=>one_for_one,intensity=>3,period=>10},[
    #{id=>reddit_server,start=>{reddit_server,start_link,[]},restart=>permanent,shutdown=>5000,type=>worker,modules=>[reddit_server]}
  ]}}.
