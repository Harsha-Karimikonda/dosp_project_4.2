-module(reddit_cli).
-export([main/1,request/6,command/2,verify_download/2]).
main(Args) ->
  {Opts,Rest}=options(Args,#{url=>"http://127.0.0.1:8080",user=><<>>,verbose=>false,bonus=>reddit_tools:default_mode()=:=bonus}),
  {ok,_}=application:ensure_all_started(inets),
  case maps:get(bonus,Opts) orelse maps:is_key(key,Opts) of true->reddit_tools:crypto_ready(); false->ok end,
  case Rest of
    ["shell"] -> shell(Opts);
    _ -> case command(Rest,Opts) of {S,_} when S>=200,S<300 -> ok; _->halt(1) end
  end.
options(["--url",V|Xs],O)->options(Xs,O#{url:=V});
options(["--user",V|Xs],O)->options(Xs,O#{user:=unicode:characters_to_binary(V)});
options(["--key",V|Xs],O)->options(Xs,O#{key=>V});
options(["--verbose"|Xs],O)->options(Xs,O#{verbose:=true});
options(["--bonus"|Xs],O)->options(Xs,O#{bonus:=true});
options(Rest,O)->{O,Rest}.
shell(O) ->
  io:format("Enter a JSON array of command arguments, e.g. [\"feed\"]. Enter quit to exit.~n"),
  shell_loop(O).
shell_loop(O) ->
  case io:get_line("reddit> ") of
    eof->ok;
    "quit\n"->ok;
    Line->
      try Args=json:decode(unicode:characters_to_binary(Line)),
          true=is_list(Args),
          command([unicode:characters_to_list(X)||X<-Args],O)
      catch C:R->io:format("~p: ~p~n",[C,R]) end,
      shell_loop(O)
  end.
command(["keygen",Dir],_) -> reddit_tools:crypto_ready(), Result=reddit_crypto:generate(Dir), print(Result), {200,Result};
command(Args,O) ->
  {Method,Path,Body}=operation(Args,O),
  {Status,Response}=request(maps:get(url,O),maps:get(user,O),Method,Path,Body,maps:get(verbose,O)),
  case Status>=200 andalso Status<300 andalso maps:get(bonus,O) of
    true->verify_download(Response,O);
    false->ok
  end,
  print(#{status=>Status,response=>Response}),
  {Status,Response}.
operation(["register",Name],_) -> {post,"/users",#{username=>b(Name)}};
operation(["register",Name,Pub],_) -> {ok,Pem}=file:read_file(Pub), {post,"/users",#{username=>b(Name),public_key=>Pem}};
operation(["communities"],_) -> {get,"/subreddits",#{}};
operation(["create",C],_) -> {post,"/subreddits",#{name=>b(C)}};
operation(["join",C],_) -> {put,"/subreddits/"++enc(C)++"/subscription",#{}};
operation(["leave",C],_) -> {delete,"/subreddits/"++enc(C)++"/subscription",#{}};
operation(["post",C,T],O) -> operation(["post",C,T,"null"],O);
operation(["post",C,T,Original],O) ->
  Orig=number_or_null(Original),
  P=#{author=>maps:get(user,O),community=>b(C),text=>b(T),original=>Orig},
  B=case maps:find(key,O) of
    error->maps:remove(author,P);
    {ok,File}->{ok,Pem}=file:read_file(File), (maps:remove(author,P))#{signature=>reddit_crypto:sign(P,Pem)}
  end,
  {post,"/posts",B};
operation(["get",I],_) -> {get,"/posts/"++I,#{}};
operation(["thread",I],_) -> {get,"/posts/"++I++"/comments",#{}};
operation(["comment",I,T],O) -> operation(["comment",I,T,"null"],O);
operation(["comment",I,T,Parent],_) -> {post,"/posts/"++I++"/comments",#{text=>b(T),parent=>number_or_null(Parent)}};
operation(["vote",Kind,I,D],_) when Kind=:= "post";Kind=:= "comment" -> {put,"/"++Kind++"s/"++I++"/vote",#{direction=>list_to_integer(D)}};
operation(["karma",N],_) -> {get,"/users/"++enc(N)++"/karma",#{}};
operation(["public-key",N],_) -> {get,"/users/"++enc(N)++"/public-key",#{}};
operation(["online",Bool],O) when Bool=:= "true";Bool=:= "false" ->
  {put,"/users/"++enc(binary_to_list(maps:get(user,O)))++"/online",#{online=>Bool=:= "true"}};
operation(["feed"|Paging],_) -> {get,"/feed"++paging(Paging,[]),#{}};
operation(["search",Q|Paging],_) -> {get,"/search"++paging(Paging,[{"q",Q}]),#{}};
operation(["send",To,T],_) -> {post,"/messages",#{recipient=>b(To),text=>b(T)}};
operation(["reply",I,T],_) -> {post,"/messages/"++I++"/replies",#{text=>b(T)}};
operation(["inbox"|Paging],_) -> {get,"/inbox"++paging(Paging,[]),#{}};
operation(_,_) -> error({usage,"See README.md for client commands"}).
paging([],Q)->query(Q);
paging([Limit],Q)->query(Q++[{"limit",Limit}]);
paging([Limit,Before],Q)->query(Q++[{"limit",Limit},{"before",Before}]);
paging(_,_) -> error(invalid_pagination).
query([])->"";
query(Q)->"?"++uri_string:compose_query(Q).
enc(S)->uri_string:quote(S).
b(S)->unicode:characters_to_binary(S).
number_or_null("null")->null;
number_or_null(S)->list_to_integer(S).
request(Url,User,Method,Path,Body,Verbose) ->
  Headers=[{"x-user",unicode:characters_to_list(User)}],
  Full=Url++"/api/v1"++Path,
  Json=iolist_to_binary(json:encode(Body)),
  Req=case Method of get->{Full,Headers}; delete->{Full,Headers}; _->{Full,Headers,"application/json",Json} end,
  case Verbose of true->io:format("CLIENT ~s ~s user=~ts~n",[string:uppercase(atom_to_list(Method)),Full,User]); false->ok end,
  case httpc:request(Method,Req,[{timeout,7000},{connect_timeout,3000}],[{body_format,binary}]) of
    {ok,{{_,Status,_},_,Bytes}} ->
      Decoded=try json:decode(Bytes) catch _:_ -> #{<<"error">>=><<"non_json_response">>} end,
      case Verbose of true->io:format("CLIENT status=~p body=~ts~n",[Status,Bytes]); false->ok end,
      {Status,Decoded};
    {error,Reason}->error({http_failed,Reason})
  end.
verify_download(M,O) when is_map(M) ->
  case M of
    #{<<"author">>:=Author,<<"community">>:=C,<<"text">>:=T,<<"original">>:=Original} ->
      {200,#{<<"data">>:=#{<<"public_key">>:=Pem}}}=request(maps:get(url,O),maps:get(user,O),get,
        "/users/"++enc(binary_to_list(Author))++"/public-key",#{},maps:get(verbose,O)),
      P=#{author=>Author,community=>C,text=>T,original=>Original},
      case maps:get(<<"signature_version">>,M,0)=:=1 andalso reddit_crypto:verify(P,maps:get(<<"signature">>,M,<<>>),Pem) of
        true->io:format("SIGNATURE verified post=~p author=~ts~n",[maps:get(<<"id">>,M),Author]);
        false->error({integrity_error,maps:get(<<"id">>,M)})
      end;
    _ -> lists:foreach(fun(V)->verify_download(V,O) end,maps:values(M))
  end;
verify_download(L,O) when is_list(L) -> lists:foreach(fun(V)->verify_download(V,O) end,L);
verify_download(_,_) -> ok.
print(V) -> io:format("~ts~n",[iolist_to_binary(json:encode(V))]).
