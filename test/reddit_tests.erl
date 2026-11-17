-module(reddit_tests).
-include_lib("eunit/include/eunit.hrl").
fixture() ->
  S=reddit_engine:new(),
  S1=ok_state(S,<<>>,{register,<<"alice">>}),
  S2=ok_state(S1,<<>>,{register,<<"bob">>}),
  S3=ok_state(S2,<<>>,{register,<<"eve">>}),
  S4=ok_state(S3,<<"alice">>,{create,<<"erlang">>}),
  ok_state(S4,<<"bob">>,{join,<<"erlang">>}).
ok_state(S,U,Op) -> {Next,{ok,_}}=reddit_engine:apply(S,U,Op),Next.
created(S,U,Op) -> {Next,{ok,{created,Id}}}=reddit_engine:apply(S,U,Op),{Next,Id}.
registration_test() ->
  S=fixture(),
  ?assertEqual({S,{error,duplicate}},reddit_engine:apply(S,<<>>,{register,<<"alice">>})),
  ?assertEqual({S,{error,invalid}},reddit_engine:apply(S,<<>>,{register,<<" ">>})),
  ?assertEqual({S,{error,not_found}},reddit_engine:apply(S,<<"missing">>,{join,<<"erlang">>})).
membership_test() ->
  S=ok_state(fixture(),<<"bob">>,{join,<<"erlang">>}),
  ?assertEqual(2,map_size(maps:get(members,maps:get(<<"erlang">>,maps:get(communities,S))))),
  S2=ok_state(S,<<"bob">>,{leave,<<"erlang">>}),
  ?assertEqual({S2,{error,forbidden}},reddit_engine:apply(S2,<<"bob">>,{post,<<"erlang">>,<<"hello">>,none})),
  ?assertEqual({S,{error,duplicate}},reddit_engine:apply(S,<<"alice">>,{create,<<"erlang">>})).
nested_comments_test() ->
  {S,P}=created(fixture(),<<"alice">>,{post,<<"erlang">>,<<"hello">>,none}),
  {S1,A}=created(S,<<"bob">>,{comment,P,none,<<"root">>}),
  {S2,B}=created(S1,<<"alice">>,{comment,P,A,<<"child">>}),
  {S3,C}=created(S2,<<"bob">>,{comment,P,B,<<"grandchild">>}),
  {_,{ok,{comments,Comments}}}=reddit_engine:apply(S3,<<"alice">>,{thread,P}),
  ?assertEqual([none,A,B],[maps:get(parent,X)||X<-Comments]),
  ?assertEqual([C],maps:get(B,maps:get(children,S3))),
  {S4,Other}=created(S3,<<"alice">>,{post,<<"erlang">>,<<"other">>,none}),
  ?assertEqual({S4,{error,invalid}},reddit_engine:apply(S4,<<"alice">>,{comment,Other,A,<<"bad">>})),
  ?assertEqual({S4,{error,forbidden}},reddit_engine:apply(S4,<<"eve">>,{comment,P,none,<<"bad">>})).
vote_karma_test() ->
  {S,P}=created(fixture(),<<"alice">>,{post,<<"erlang">>,<<"hello">>,none}),
  {S1,{ok,{score,1}}}=reddit_engine:apply(S,<<"bob">>,{vote,{post,P},1}),
  {S2,{ok,{score,1}}}=reddit_engine:apply(S1,<<"bob">>,{vote,{post,P},1}),
  ?assertMatch({_,{ok,{score,1}}},reddit_engine:apply(S2,<<"bob">>,{karma,<<"alice">>})),
  {S3,{ok,{score,-1}}}=reddit_engine:apply(S2,<<"bob">>,{vote,{post,P},-1}),
  ?assertMatch({_,{ok,{score,-1}}},reddit_engine:apply(S3,<<"bob">>,{karma,<<"alice">>})),
  {S4,{ok,{score,0}}}=reddit_engine:apply(S3,<<"bob">>,{vote,{post,P},0}),
  {S5,C}=created(S4,<<"alice">>,{comment,P,none,<<"hi">>}),
  {S6,{ok,{score,1}}}=reddit_engine:apply(S5,<<"bob">>,{vote,{comment,C},1}),
  ?assertMatch({_,{ok,{score,1}}},reddit_engine:apply(S6,<<"bob">>,{karma,<<"alice">>})),
  ?assertEqual({S6,{error,forbidden}},reddit_engine:apply(S6,<<"alice">>,{vote,{post,P},1})),
  ?assertEqual({S6,{error,invalid}},reddit_engine:apply(S6,<<"bob">>,{vote,{post,P},2})),
  ?assertEqual({S6,{error,not_found}},reddit_engine:apply(S6,<<"bob">>,{vote,{post,999},1})).
feed_pagination_test() ->
  {S,A}=created(fixture(),<<"alice">>,{post,<<"erlang">>,<<"a">>,none}),
  {S1,B}=created(S,<<"alice">>,{post,<<"erlang">>,<<"b">>,none}),
  ?assertMatch({_,{ok,{posts,[#{id:=B}]}}},reddit_engine:apply(S1,<<"bob">>,{feed,none,1})),
  ?assertMatch({_,{ok,{posts,[#{id:=A}]}}},reddit_engine:apply(S1,<<"bob">>,{feed,B,1})),
  ?assertMatch({_,{ok,{posts,[]}}},reddit_engine:apply(S1,<<"eve">>,{feed,none,20})),
  ?assertEqual({S1,{error,invalid}},reddit_engine:apply(S1,<<"bob">>,{feed,none,101})).
feed_multiple_communities_test() ->
  S=ok_state(fixture(),<<"bob">>,{create,<<"otp">>}),
  {S1,A}=created(S,<<"bob">>,{post,<<"otp">>,<<"old">>,none}),
  {S2,B}=created(S1,<<"alice">>,{post,<<"erlang">>,<<"new">>,none}),
  ?assertMatch({_,{ok,{posts,[#{id:=B},#{id:=A}]}}},reddit_engine:apply(S2,<<"bob">>,{feed,none,20})),
  S3=ok_state(S2,<<"bob">>,{leave,<<"otp">>}),
  ?assertMatch({_,{ok,{posts,[#{id:=B}]}}},reddit_engine:apply(S3,<<"bob">>,{feed,none,20})).
repost_test() ->
  {S,A}=created(fixture(),<<"alice">>,{post,<<"erlang">>,<<"a">>,none}),
  {S1,B}=created(S,<<"bob">>,{post,<<"erlang">>,<<"repost">>,A}),
  ?assertEqual(A,maps:get(original,maps:get(B,maps:get(posts,S1)))),
  ?assertEqual(1,maps:get(reposts,S1)),
  ?assertEqual({S1,{error,not_found}},reddit_engine:apply(S1,<<"bob">>,{post,<<"erlang">>,<<"bad">>,999})).
messaging_privacy_test() ->
  {S,A}=created(fixture(),<<"alice">>,{send_message,<<"bob">>,<<"hello">>}),
  ?assertMatch({_,{ok,{messages,[#{sender:= <<"alice">>}]}}},reddit_engine:apply(S,<<"bob">>,{inbox,none,20})),
  ?assertMatch({_,{ok,{messages,[]}}},reddit_engine:apply(S,<<"eve">>,{inbox,none,20})),
  ?assertEqual({S,{error,forbidden}},reddit_engine:apply(S,<<"eve">>,{reply_message,A,<<"intrude">>})),
  {S1,B}=created(S,<<"bob">>,{reply_message,A,<<"reply">>}),
  ?assertMatch({_,{ok,{messages,[#{id:=B,parent:=A}]}}},reddit_engine:apply(S1,<<"alice">>,{inbox,none,20})),
  ?assertEqual({S1,{error,not_found}},reddit_engine:apply(S1,<<"alice">>,{send_message,<<"missing">>,<<"hello">>})).
disconnect_test() ->
  S=ok_state(fixture(),<<"bob">>,{online,false}),
  ?assertEqual({S,{error,offline}},reddit_engine:apply(S,<<"bob">>,{feed,none,20})),
  {S1,_}=created(S,<<"alice">>,{send_message,<<"bob">>,<<"offline delivery">>}),
  S2=ok_state(S1,<<"bob">>,{online,true}),
  ?assertMatch({_,{ok,{messages,[_]}}},reddit_engine:apply(S2,<<"bob">>,{inbox,none,20})),
  ?assertMatch({_,{ok,{created,_}}},reddit_engine:apply(S2,<<"bob">>,{post,<<"erlang">>,<<"still joined">>,none})).
invalid_text_test() ->
  S=fixture(),
  ?assertEqual({S,{error,invalid}},reddit_engine:apply(S,<<"alice">>,{post,<<"erlang">>,<<>>,none})),
  ?assertEqual({S,{error,invalid}},reddit_engine:apply(S,<<"alice">>,{send_message,<<"bob">>,<<" ">>})).
malformed_request_test() ->
  S=fixture(),?assertEqual({S,{error,invalid}},reddit_engine:apply(S,<<"alice">>,unknown_operation)).

