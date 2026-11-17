-module(reddit_tools).
-export([main/1,default_mode/0,crypto_ready/0,start/3]).
default_mode() -> {ok,[C]}=file:consult("config/default.config"), maps:get(mode,C).
crypto_ready() ->
  case application:ensure_all_started(public_key) of
    {ok,_}->ok;
    Error->error({crypto_unavailable,"Install complete Erlang/OTP including crypto and public_key",Error})
  end.
start(Mode,Address,Port) ->
  case Mode of bonus->crypto_ready(); base->ok end,
  ok=application:load(reddit),
  ok=application:set_env(reddit,mode,Mode),
  {ok,_}=application:ensure_all_started(reddit),
  reddit_http:start(Address,Port).
main(["build"]) -> io:format("Build passed~n");
main(["test"]) ->
  case eunit:test([reddit_tests,reddit_rest_tests],[verbose]) of ok->ok; _->halt(1) end;
main(["test-bonus"]) -> crypto_ready(),
  case eunit:test(reddit_bonus_tests,[verbose]) of ok->ok; _->halt(1) end;
main(["server"|Args]) ->
  {Mode,Address,Port}=server_options(Args,{default_mode(),{127,0,0,1},8080}),
  {ok,_}=start(Mode,Address,Port),
  io:format("READY mode=~p address=~p port=~p (Ctrl-C to stop)~n",[Mode,Address,Port]),
  receive stop->ok end;
main(["client"|Args]) -> reddit_cli:main(Args);
main(["demo"|Args]) -> reddit_demo:run(Args);
main(["report"]) -> run_python("scripts/report.py");
main(["package"|Args]) ->
  case Args of []->run_python("scripts/package.py"); ["--final"]->run_python("scripts/package.py --final") end;
main(_) -> io:format("Commands: build | test | test-bonus | server [--mode base|bonus] [--bind IP] [--port N] | client ... | demo [base|bonus] | report | package [--final]~n").
server_options([],O)->O;
server_options(["--mode","base"|Xs],{_,A,P})->server_options(Xs,{base,A,P});
server_options(["--mode","bonus"|Xs],{_,A,P})->server_options(Xs,{bonus,A,P});
server_options(["--bind",V|Xs],{M,_,P})->{ok,A}=inet:parse_address(V),server_options(Xs,{M,A,P});
server_options(["--port",V|Xs],{M,A,_})->P=list_to_integer(V),true=P>0 andalso P=<65535,server_options(Xs,{M,A,P});
server_options(_,_) -> error(invalid_server_options).
run_python(Script) ->
  Port=open_port({spawn,"python3 "++Script},[exit_status,use_stdio,stderr_to_stdout,binary]),
  collect(Port).
collect(Port) -> receive
  {Port,{data,B}}->io:put_chars(B),collect(Port);
  {Port,{exit_status,0}}->ok;
  {Port,{exit_status,N}}->error({tool_failed,N})
end.
