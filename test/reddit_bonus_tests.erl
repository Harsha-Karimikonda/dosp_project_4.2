-module(reddit_bonus_tests).
-include_lib("eunit/include/eunit.hrl").
-export([tamper_state/1]).
bonus_test_() -> {timeout,60,fun checks/0}.
checks() ->
  Dir=filename:join("build","bonus-test-"++integer_to_list(erlang:system_time(microsecond))++"-"++integer_to_list(erlang:unique_integer([positive]))),
  reddit_crypto:generate(Dir),reddit_crypto:generate(Dir++"-other"),
  {ok,Pub}=file:read_file(filename:join(Dir,"public.pem")),
  {ok,Priv}=file:read_file(filename:join(Dir,"private.pem")),
  {ok,Wrong}=file:read_file(filename:join(Dir++"-other","public.pem")),
  P=#{author=><<"alice">>,community=><<"erlang">>,text=><<"Signed REST">>,original=>none},
  Sig=reddit_crypto:sign(P,Priv),
  ?assert(reddit_crypto:verify(P,Sig,Pub)),
  ?assertNot(reddit_crypto:verify(P,Sig,Wrong)),
  ?assertNot(reddit_crypto:valid_public(Priv)),
  ?assertNot(reddit_crypto:valid_public(<<"bad">>)),
  ?assertNot(reddit_crypto:verify(P,<<"!">>,Pub)),
  [?assertNot(reddit_crypto:verify(P#{K=>V},Sig,Pub)) || {K,V}<-[{author,<<"bob">>},{community,<<"other">>},{text,<<"tampered">>},{original,1}]],
  ?assert(reddit_crypto:verify(P#{score=>99,id=>42},Sig,Pub)),
  S=reddit_engine:new(bonus),
  ?assertMatch({_,{error,invalid_key}},reddit_engine:apply(S,<<>>,{register,<<"x">>})),
  {S1,{ok,done}}=reddit_engine:apply(S,<<>>,{register,<<"alice">>,Pub}),
  {S2,{ok,done}}=reddit_engine:apply(S1,<<"alice">>,{create,<<"erlang">>}),
  ?assertMatch({_,{error,invalid_signature}},reddit_engine:apply(S2,<<"alice">>,{post,<<"erlang">>,<<"x">>,none})),
  {S3,{ok,{created,Id}}}=reddit_engine:apply(S2,<<"alice">>,{signed_post,<<"erlang">>,<<"Signed REST">>,none,Sig}),
  ?assertMatch({_,{ok,{post,_}}},reddit_engine:apply(S3,<<"alice">>,{get_post,Id})),
  Damaged=tamper_state(S3),
  [?assertMatch({_,{error,integrity_error}},reddit_engine:apply(Damaged,<<"alice">>,Op)) || Op<-[{get_post,Id},{feed,none,20},{search,<<"tampered">>,none,20}]],
  http_checks(Pub,Priv,Sig).
tamper_state(S) ->
  Posts=maps:get(posts,S),
  S#{posts:=maps:map(fun(_,Post)->Post#{text:= <<"tampered">>} end,Posts)}.
http_checks(Pub,Priv,Sig) ->
  {ok,H}=reddit_tools:start(bonus,{127,0,0,1},0),
  Url="http://127.0.0.1:"++integer_to_list(proplists:get_value(port,httpd:info(H))),
  R=fun(M,Path,B)->reddit_cli:request(Url,<<"alice">>,M,Path,B,false) end,
  try
    ?assertMatch({400,_},R(post,"/users",#{username=><<"bad">>,public_key=><<"bad">>})),
    ?assertMatch({201,_},R(post,"/users",#{username=><<"alice">>,public_key=>Pub})),
    ?assertMatch({409,_},R(post,"/users",#{username=><<"alice">>,public_key=>Pub})),
    ?assertMatch({200,#{<<"data">>:=#{<<"public_key">>:=Pub}}},R(get,"/users/alice/public-key",#{})),
    ?assertMatch({201,_},R(post,"/subreddits",#{name=><<"erlang">>})),
    B=#{community=><<"erlang">>,text=><<"Signed REST">>},
    ?assertMatch({400,_},R(post,"/posts",B)),
    ?assertMatch({400,_},R(post,"/posts",B#{signature=><<"bad">>})),
    ?assertMatch({201,_},R(post,"/posts",B#{signature=>Sig})),
    ?assertMatch({400,_},R(post,"/posts",B#{text=><<"changed">>,signature=>Sig})),
    P=#{author=><<"alice">>,community=><<"erlang">>,text=><<"Repost">>,original=>1},
    ?assertMatch({201,_},R(post,"/posts",#{community=><<"erlang">>,text=><<"Repost">>,original=>1,signature=>reddit_crypto:sign(P,Priv)})),
    {200,Good}=R(get,"/posts/1",#{}),
    O=#{url=>Url,user=><<"alice">>,verbose=>false,bonus=>true},
    %% Uses the same independent key-lookup verification as normal CLI downloads.
    ?assertMatch({200,_},reddit_cli:command(["get","1"],O)),
    #{<<"data">>:=#{<<"post">>:=Downloaded}}=Good,
    ?assertError({integrity_error,1},reddit_cli:verify_download(Downloaded#{<<"text">>:= <<"modified in transit">>},O)),
    sys:replace_state(reddit_server,fun tamper_state/1),
    [?assertMatch({422,#{<<"error">>:= <<"integrity_error">>}},R(get,Path,#{})) || Path<-["/posts/1","/feed","/search?q=tampered"]]
  after reddit_http:stop(H),application:stop(reddit) end.
