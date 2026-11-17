%% Each CLI invocation is a separate BEAM OS process; all traffic uses HTTP.
-module(reddit_demo).
-export([run/1]).
run(Args) ->
  Mode=case Args of []->reddit_tools:default_mode(); ["base"]->base; ["bonus"]->bonus end,
  {ok,H}=reddit_tools:start(Mode,{127,0,0,1},0),
  Port=proplists:get_value(port,httpd:info(H)),
  Url="http://127.0.0.1:"++integer_to_list(Port),
  Dir=filename:join("build","demo-"++integer_to_list(erlang:system_time(microsecond))++"-"++integer_to_list(erlang:unique_integer([positive]))),
  try
    Keys=case Mode of
      base->#{};
      bonus->maps:from_list([{U,begin D=filename:join(Dir,U),reddit_crypto:generate(D),D end}||U<-["alice","bob"]])
    end,
    C=fun(U,Command)->wait(child(Url,U,Command,Mode,Keys)) end,
    [C(U,case Mode of base->["register",U]; bonus->["register",U,filename:join(maps:get(U,Keys),"public.pem")] end)||U<-["alice","bob"]],
    C("alice",["create","erlang"]), C("bob",["join","erlang"]),
    C("alice",["communities"]),
    C("alice",["post","erlang","Hello REST"]),
    C("bob",["comment","1","Root comment"]),
    C("alice",["comment","1","Nested reply","2"]),
    C("bob",["thread","1"]),
    %% Concurrent clients repeat the same vote: the score must remain one.
    A=child(Url,"bob",["vote","post","1","1"],Mode,Keys),
    B=child(Url,"bob",["vote","post","1","1"],Mode,Keys),
    wait(A),wait(B),
    C("alice",["vote","comment","2","1"]),
    C("bob",["karma","alice"]), C("alice",["karma","bob"]),
    C("bob",["post","erlang","Repost via HTTP","1"]),
    C("bob",["get","1"]),C("bob",["feed","1"]),C("bob",["feed","20","4"]),
    C("bob",["search","rest"]),
    C("bob",["online","false"]),C("alice",["send","bob","Delivered while offline"]),
    C("bob",["online","true"]),C("bob",["inbox"]),C("bob",["reply","5","Received!"]),C("alice",["inbox"]),
    C("bob",["leave","erlang"]),C("bob",["join","erlang"]),
    case Mode of bonus->C("bob",["public-key","alice"]);base->ok end,
    {200,#{<<"data">>:=#{<<"score">>:=1}}}=reddit_cli:request(Url,<<"bob">>,get,"/users/alice/karma",#{},false),
    io:format("DEMO PASS mode=~p server_os_pid=~s (independent CLI OS processes shown above)~n",[Mode,os:getpid()])
  after reddit_http:stop(H),application:stop(reddit) end.
child(Url,U,Command,Mode,Keys) ->
  Extra=case Mode of base->[];bonus->["--bonus","--key",filename:join(maps:get(U,Keys),"private.pem")] end,
  Erl=filename:join([code:root_dir(),"bin","erl"]),
  CryptoPath=case code:which(crypto) of non_existing->[];P->["-pa",filename:dirname(P)] end,
  Args=["+S","2:2","-noshell","-pa",filename:absname("build/ebin")]++CryptoPath++
    ["-eval","reddit_cli:main(init:get_plain_arguments()), halt().","-extra","--url",Url,"--user",U,"--verbose"]++Extra++Command,
  Pid=open_port({spawn_executable,Erl},[binary,exit_status,use_stdio,stderr_to_stdout,{args,Args}]),
  {os_pid,OsPid}=erlang:port_info(Pid,os_pid),
  io:format("CLIENT_PROCESS os_pid=~p user=~s command=~p~n",[OsPid,U,Command]),Pid.
wait(P) -> receive
  {P,{data,Bytes}}->io:put_chars(Bytes),wait(P);
  {P,{exit_status,0}}->ok;
  {P,{exit_status,N}}->error({client_failed,N})
after 30000->port_close(P),error(client_timeout)
end.
