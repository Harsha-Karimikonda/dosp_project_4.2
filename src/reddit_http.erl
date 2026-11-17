-module(reddit_http).
-include_lib("inets/include/httpd.hrl").
-export([start/2,stop/1,do/1]).
start(Address,Port) ->
  ok=filelib:ensure_dir("build/http/placeholder"),
  inets:start(httpd,[{port,Port},{bind_address,Address},{server_name,"reddit"},
    {server_root,filename:absname("build/http")},{document_root,filename:absname("build/http")},
    {modules,[?MODULE]},{max_body_size,65536},{max_header_size,16384}]).
stop(Pid) -> inets:stop(httpd,Pid).
do(#mod{method=Method,request_uri=Uri,parsed_header=Headers,entity_body=Body,data=Data}) ->
  Start=erlang:monotonic_time(microsecond),
  RequestId=integer_to_list(erlang:unique_integer([positive,monotonic])),
  User=list_to_binary(proplists:get_value("x-user",Headers,"")),
  {Status,Response}=try
    #{path:=Path}=Parts=uri_string:parse(Uri),
    Segments=[unicode:characters_to_binary(uri_string:percent_decode(X)) || X<-string:split(Path,"/",all), X=/=""],
    Query=maps:from_list([{list_to_binary(K),list_to_binary(V)} || {K,V}<-uri_string:dissect_query(maps:get(query,Parts,""))]),
    B=case Body of []->#{}; <<>>->#{}; _->json:decode(iolist_to_binary(Body)) end,
    true=is_map(B),
    route(Method,Segments,User,B,Query)
  catch
    throw:{http,Code,Why} -> {Code,#{error=>Why}};
    _:_ -> {400,#{error=>invalid_request}}
  end,
  Bytes=iolist_to_binary(json:encode(clean(Response#{request_id=>list_to_binary(RequestId)}))),
  Elapsed=erlang:monotonic_time(microsecond)-Start,
  io:format("HTTP id=~s method=~s path=~ts user=~ts status=~p elapsed_us=~p~n",[RequestId,Method,Uri,User,Status,Elapsed]),
  Head=[{code,Status},{content_type,"application/json; charset=utf-8"},{content_length,integer_to_list(byte_size(Bytes))}],
  {break,[{response,{response,Head,Bytes}}|Data]}.
route("GET",[<<"health">>],_,_,_) -> {200,#{status=>ok,mode=>application:get_env(reddit,mode,base)}};
route(M,[<<"api">>,<<"v1">>|Path],U,B,Q) ->
  case {M,Path} of
    {"POST",[<<"users">>]} -> call(<<>>,{register,req(B,<<"username">>),maps:get(<<"public_key">>,B,<<>>)},201);
    _ when U=:= <<>> -> throw({http,400,missing_user});
    _ -> api(M,Path,U,B,Q)
  end;
route(_,_,_,_,_) -> throw({http,404,not_found}).
api("GET",[<<"users">>,N,<<"karma">>],U,_,_) -> call(U,{karma,N},200);
api("GET",[<<"users">>,N,<<"public-key">>],U,_,_) -> call(U,{public_key,N},200);
api("PUT",[<<"users">>,N,<<"online">>],U,B,_) when N=:=U -> call(U,{online,req(B,<<"online">>)},200);
api("PUT",[<<"users">>,_,<<"online">>],_,_,_) -> throw({http,403,forbidden});
api("GET",[<<"subreddits">>],U,_,_) -> call(U,communities,200);
api("POST",[<<"subreddits">>],U,B,_) -> call(U,{create,req(B,<<"name">>)},201);
api("PUT",[<<"subreddits">>,C,<<"subscription">>],U,_,_) -> call(U,{join,C},200);
api("DELETE",[<<"subreddits">>,C,<<"subscription">>],U,_,_) -> call(U,{leave,C},200);
api("POST",[<<"posts">>],U,B,_) ->
  C=req(B,<<"community">>), T=req(B,<<"text">>), O=optional_id(maps:get(<<"original">>,B,null)),
  Op=case application:get_env(reddit,mode,base) of
    base->{post,C,T,O}; bonus->{signed_post,C,T,O,req(B,<<"signature">>)} end,
  call(U,Op,201);
api("GET",[<<"posts">>,I],U,_,_) -> call(U,{get_post,id(I)},200);
api("GET",[<<"posts">>,I,<<"comments">>],U,_,_) -> call(U,{thread,id(I)},200);
api("POST",[<<"posts">>,I,<<"comments">>],U,B,_) ->
  call(U,{comment,id(I),optional_id(maps:get(<<"parent">>,B,null)),req(B,<<"text">>)},201);
api("PUT",[Kind,I,<<"vote">>],U,B,_) when Kind=:= <<"posts">>; Kind=:= <<"comments">> ->
  K=case Kind of <<"posts">>->post; _->comment end,
  call(U,{vote,{K,id(I)},req(B,<<"direction">>)},200);
api("GET",[<<"feed">>],U,_,Q) -> {Before,Limit}=page(Q), call(U,{feed,Before,Limit},200);
api("GET",[<<"search">>],U,_,Q) -> {Before,Limit}=page(Q), call(U,{search,req(Q,<<"q">>),Before,Limit},200);
api("POST",[<<"messages">>],U,B,_) -> call(U,{send_message,req(B,<<"recipient">>),req(B,<<"text">>)},201);
api("POST",[<<"messages">>,I,<<"replies">>],U,B,_) -> call(U,{reply_message,id(I),req(B,<<"text">>)},201);
api("GET",[<<"inbox">>],U,_,Q) -> {Before,Limit}=page(Q), call(U,{inbox,Before,Limit},200);
api(_,Path,_,_,_) ->
  case known(Path) of true->throw({http,405,method_not_allowed}); false->throw({http,404,not_found}) end.
known([X]) -> lists:member(X,[<<"subreddits">>,<<"users">>,<<"posts">>,<<"feed">>,<<"search">>,<<"messages">>,<<"inbox">>]);
known([<<"posts">>,_]) -> true;
known([X,_,Y]) ->
  lists:member({X,Y},[{<<"posts">>,<<"comments">>},{<<"posts">>,<<"vote">>},{<<"comments">>,<<"vote">>},
    {<<"users">>,<<"karma">>},{<<"users">>,<<"online">>},{<<"users">>,<<"public-key">>},
    {<<"subreddits">>,<<"subscription">>},{<<"messages">>,<<"replies">>}]);
known(_) -> false.
req(M,K) -> case maps:find(K,M) of {ok,V}->V; error->throw({http,400,missing_field}) end.
id(B) when is_binary(B) -> id(binary_to_integer(B));
id(I) when is_integer(I),I>0 -> I;
id(_) -> throw({http,400,invalid_id}).
optional_id(null) -> none;
optional_id(I) -> id(I).
page(Q) ->
  Before=case maps:find(<<"before">>,Q) of error->none; {ok,V}->id(V) end,
  Limit=binary_to_integer(maps:get(<<"limit">>,Q,<<"20">>)),
  case Limit>=1 andalso Limit=<100 of true->{Before,Limit}; false->throw({http,400,invalid_limit}) end.
call(U,Op,Status) ->
  case reddit_server:request(node(),U,Op,5000) of
    {ok,V} -> {Status,#{data=>value(V)}};
    {error,E} -> {error_status(E),#{error=>E}}
  end.
value(done) -> #{ok=>true};
value({created,I}) -> #{id=>I};
value({K,V}) when K=:=posts; K=:=post; K=:=comments; K=:=messages; K=:=score -> #{K=>V};
value(M) when is_map(M) -> M.
error_status(duplicate)->409;
error_status(not_found)->404;
error_status(forbidden)->403;
error_status(offline)->403;
error_status(timeout)->504;
error_status(unavailable)->503;
error_status(integrity_error)->422;
error_status(_)->400.
clean(none)->null;
clean(M) when is_map(M)->maps:map(fun(_,V)->clean(V) end,M);
clean(L) when is_list(L)->[clean(X)||X<-L];
clean(X)->X.
