%% Pure state transitions. reddit_server serializes these operations atomically.
-module(reddit_engine).
-export([new/0, new/1, apply/3]).
-type user() :: binary().
-type operation() :: {register,binary()} | {create,binary()} | {join,binary()} |
  {leave,binary()} | {post,binary(),binary(),none | pos_integer()} |
  {comment,pos_integer(),none | pos_integer(),binary()} |
  {vote,{post | comment,pos_integer()},-1 | 0 | 1} |
  {feed,none | pos_integer(),pos_integer()} | {thread,pos_integer()} |
  {karma,binary()} | {send_message,binary(),binary()} |
  {reply_message,pos_integer(),binary()} | {inbox,none | pos_integer(),pos_integer()} |
  {online,boolean()} | {register,binary(),binary()} |
  {signed_post,binary(),binary(),none | pos_integer(),binary()} |
  {get_post,pos_integer()} | {public_key,binary()} | communities |
  {search,binary(),none | pos_integer(),pos_integer()} | inspect.
-export_type([operation/0]).

new() -> new(base).
new(Mode) -> #{mode=>Mode,users=>#{},communities=>#{},subscriptions=>#{},posts=>#{},community_posts=>#{},
  comments=>#{},post_comments=>#{},children=>#{},votes=>#{},messages=>#{},inboxes=>#{},next=>1,reposts=>0}.

-spec apply(map(), user(), operation()) -> {map(), {ok,term()} | {error,atom()}}.
apply(S,U,Op) ->
  try dispatch(S,U,Op)
  catch error:_ -> {S,{error,invalid}} end.

dispatch(S,_,{register,Name,Pem}) ->
  case maps:get(mode,S) of
    base -> transition(S,<<>>,{register,Name});
    bonus ->
      case reddit_crypto:valid_public(Pem) of
        false -> fail(S,invalid_key);
        true ->
          case transition(S,<<>>,{register,Name}) of
            {Next,{ok,done}} ->
              Users=maps:get(users,Next), A=maps:get(Name,Users),
              {Next#{users:=Users#{Name=>A#{public_key=>Pem}}},{ok,done}};
            Result -> Result
          end
      end
  end;
dispatch(S,_,{register,_}) when map_get(mode,S)=:=bonus -> fail(S,invalid_key);
dispatch(S,_,{post,_,_,_}) when map_get(mode,S)=:=bonus -> fail(S,invalid_signature);
dispatch(S,U,{signed_post,C,T,O,Sig}) when map_get(mode,S)=:=bonus ->
  case maps:find(U,maps:get(users,S)) of
    error -> fail(S,not_found);
    {ok,A} ->
      P=#{author=>U,community=>C,text=>T,original=>O},
      case reddit_crypto:verify(P,Sig,maps:get(public_key,A)) of
        false -> fail(S,invalid_signature);
        true -> case transition(S,U,{post,C,T,O}) of
          {Next,{ok,{created,Id}}} ->
            Posts=maps:get(posts,Next), Post=maps:get(Id,Posts),
            {Next#{posts:=Posts#{Id=>Post#{signature=>Sig,signature_version=>1}}},{ok,{created,Id}}};
          Result -> Result
        end
      end
  end;
dispatch(S,U,Op) ->
  case transition(S,U,Op) of
    {Next,{ok,{posts,Posts}}} -> verified(Next,Posts,{posts,Posts});
    {Next,{ok,{post,P}}} -> verified(Next,[P],{post,P});
    Result -> Result
  end.
verified(S,Posts,Result) ->
  Good=maps:get(mode,S)=:=base orelse lists:all(fun(P) ->
    A=maps:get(maps:get(author,P),maps:get(users,S)),
    maps:get(signature_version,P,0)=:=1 andalso reddit_crypto:verify(P,maps:get(signature,P,<<>>),maps:get(public_key,A)) end,Posts),
  case Good of true->{S,{ok,Result}}; false->fail(S,integrity_error) end.

transition(S,_,{register,Name}) ->
  case {valid(Name),maps:is_key(Name,maps:get(users,S))} of
    {false,_} -> fail(S,invalid);
    {_,true} -> fail(S,duplicate);
    _ -> {S#{users:=maps:put(Name,#{name=>Name,karma=>0,online=>true},maps:get(users,S)),
             subscriptions:=maps:put(Name,#{},maps:get(subscriptions,S))},{ok,done}}
  end;
transition(S,_,inspect) -> {S,{ok,stats(S)}};
transition(S,User,Op) ->
  case maps:find(User,maps:get(users,S)) of
    error -> fail(S,not_found);
    {ok,Account} ->
      case {Op,maps:get(online,Account)} of
        {{online,B},_} when is_boolean(B) ->
          {S#{users:=maps:put(User,Account#{online:=B},maps:get(users,S))},{ok,done}};
        {_,false} -> fail(S,offline);
        _ -> active(S,User,Op)
      end
  end.

active(S,_,{public_key,Name}) ->
  case maps:find(Name,maps:get(users,S)) of
    {ok,#{public_key:=Pem}} -> {S,{ok,#{public_key=>Pem}}};
    _ -> fail(S,not_found)
  end;
active(S,_,communities) ->
  Cs=[#{name=>N,members=>map_size(maps:get(members,C))} || {N,C}<-lists:sort(maps:to_list(maps:get(communities,S)))],
  {S,{ok,#{communities=>Cs}}};
active(S,_,{get_post,Id}) ->
  case maps:find(Id,maps:get(posts,S)) of {ok,P}->{S,{ok,{post,P}}}; error->fail(S,not_found) end;
active(S,_,{search,Q,Before,Limit}) when is_binary(Q),is_integer(Limit),Limit>0,Limit=<100 ->
  case valid(Q) of
    false -> fail(S,invalid);
    true ->
      Query=string:casefold(unicode:characters_to_list(Q)),
      Match=fun(B) -> string:find(string:casefold(unicode:characters_to_list(B)),Query)=/=nomatch end,
      Ps=maps:get(posts,S),
      Ids=lists:reverse(lists:sort([I || {I,P}<-maps:to_list(Ps), Match(maps:get(text,P)) orelse Match(maps:get(community,P))])),
      {S,{ok,{posts,[maps:get(I,Ps)||I<-take_before(Ids,Before,Limit)]}}}
  end;
active(S,U,{create,Name}) ->
  case {valid(Name),maps:is_key(Name,maps:get(communities,S))} of
    {false,_} -> fail(S,invalid);
    {_,true} -> fail(S,duplicate);
    _ -> active(S#{communities:=maps:put(Name,#{name=>Name,members=>#{}},maps:get(communities,S))},U,{join,Name})
  end;
active(S,U,{Action,Name}) when Action=:=join; Action=:=leave ->
  case maps:find(Name,maps:get(communities,S)) of
    error -> fail(S,not_found);
    {ok,C} ->
      Subs=maps:get(U,maps:get(subscriptions,S)), Members=maps:get(members,C),
      {NextSubs,NextMembers}=case Action of
        join -> {Subs#{Name=>true},Members#{U=>true}};
        leave -> {maps:remove(Name,Subs),maps:remove(U,Members)}
      end,
      {S#{communities:=maps:put(Name,C#{members:=NextMembers},maps:get(communities,S)),
          subscriptions:=maps:put(U,NextSubs,maps:get(subscriptions,S))},{ok,done}}
  end;
active(S,U,{post,Community,Text,Original}) ->
  SourceOk=Original=:=none orelse maps:is_key(Original,maps:get(posts,S)),
  case {maps:is_key(Community,maps:get(communities,S)),member(S,U,Community),valid(Text),SourceOk} of
    {false,_,_,_} -> fail(S,not_found);
    {_,false,_,_} -> fail(S,forbidden);
    {_,_,false,_} -> fail(S,invalid);
    {_,_,_,false} -> fail(S,not_found);
    _ ->
      Id=maps:get(next,S), P=#{id=>Id,author=>U,community=>Community,text=>Text,original=>Original,score=>0},
      Reposts=maps:get(reposts,S)+case Original of none->0; _->1 end,
      {S#{next:=Id+1,posts:=maps:put(Id,P,maps:get(posts,S)),
          community_posts:=push(maps:get(community_posts,S),Community,Id),reposts:=Reposts},{ok,{created,Id}}}
  end;
active(S,U,{comment,Post,Parent,Text}) ->
  case maps:find(Post,maps:get(posts,S)) of
    error -> fail(S,not_found);
    {ok,P} ->
      ParentOk=case Parent of
        none -> true;
        _ -> case maps:find(Parent,maps:get(comments,S)) of {ok,#{post:=Post}} -> true; _ -> false end
      end,
      case {member(S,U,maps:get(community,P)),valid(Text),ParentOk} of
        {false,_,_} -> fail(S,forbidden);
        {_,false,_} -> fail(S,invalid);
        {_,_,false} -> fail(S,invalid);
        _ ->
          Id=maps:get(next,S), C=#{id=>Id,author=>U,post=>Post,parent=>Parent,text=>Text,score=>0},
          Children=case Parent of none->maps:get(children,S); _->push(maps:get(children,S),Parent,Id) end,
          {S#{next:=Id+1,comments:=maps:put(Id,C,maps:get(comments,S)),
              post_comments:=push(maps:get(post_comments,S),Post,Id),children:=Children},{ok,{created,Id}}}
      end
  end;
active(S,U,{vote,{Kind,Id}=Target,Direction}) when Kind=:=post; Kind=:=comment ->
  Key=case Kind of post->posts; comment->comments end,
  case maps:find(Id,maps:get(Key,S)) of
    error -> fail(S,not_found);
    {ok,#{author:=U}} -> fail(S,forbidden);
    {ok,#{author:=Author,score:=Score}=Content} when Direction=:= -1; Direction=:=0; Direction=:=1 ->
      Votes=maps:get(votes,S), Delta=Direction-maps:get({U,Target},Votes,0),
      Users=maps:get(users,S), Account=maps:get(Author,Users), NewScore=Score+Delta,
      {S#{Key:=maps:put(Id,Content#{score:=NewScore},maps:get(Key,S)),
          users:=maps:put(Author,Account#{karma:=maps:get(karma,Account)+Delta},Users),
          votes:=maps:put({U,Target},Direction,Votes)},{ok,{score,NewScore}}};
    _ -> fail(S,invalid)
  end;
active(S,_,{karma,Name}) ->
  case maps:find(Name,maps:get(users,S)) of {ok,A}->{S,{ok,{score,maps:get(karma,A)}}}; _->fail(S,not_found) end;
active(S,U,{feed,Before,Limit}) when is_integer(Limit),Limit>0,Limit=<100 ->
  Lists=[take_before(maps:get(C,maps:get(community_posts,S),[]),Before,Limit)
         || C <- maps:keys(maps:get(U,maps:get(subscriptions,S)))],
  Ids=lists:sublist(lists:reverse(lists:sort(lists:append(Lists))),Limit),
  {S,{ok,{posts,[maps:get(Id,maps:get(posts,S)) || Id<-Ids]}}};
active(S,_,{thread,Post}) ->
  case maps:is_key(Post,maps:get(posts,S)) of
    false -> fail(S,not_found);
    true -> {S,{ok,{comments,[maps:get(Id,maps:get(comments,S)) || Id<-lists:reverse(maps:get(Post,maps:get(post_comments,S),[]))]}}}
  end;
active(S,U,{send_message,To,Text}) -> send(S,U,To,Text,none);
active(S,U,{reply_message,Id,Text}) ->
  case maps:find(Id,maps:get(messages,S)) of
    error -> fail(S,not_found);
    {ok,#{recipient:=U,sender:=To}} -> send(S,U,To,Text,Id);
    _ -> fail(S,forbidden)
  end;
active(S,U,{inbox,Before,Limit}) when is_integer(Limit),Limit>0,Limit=<100 ->
  {S,{ok,{messages,[maps:get(Id,maps:get(messages,S)) || Id<-take_before(maps:get(U,maps:get(inboxes,S),[]),Before,Limit)]}}};
active(S,_,_) -> fail(S,invalid).

send(S,U,To,Text,Parent) ->
  case {maps:is_key(To,maps:get(users,S)),valid(Text)} of
    {false,_} -> fail(S,not_found);
    {_,false} -> fail(S,invalid);
    _ ->
      Id=maps:get(next,S), M=#{id=>Id,sender=>U,recipient=>To,text=>Text,parent=>Parent},
      {S#{next:=Id+1,messages:=maps:put(Id,M,maps:get(messages,S)),inboxes:=push(maps:get(inboxes,S),To,Id)},{ok,{created,Id}}}
  end.
valid(Text) when is_binary(Text) -> byte_size(string:trim(Text))>0 andalso byte_size(Text)=<10000;
valid(_) -> false.
fail(S,E) -> {S,{error,E}}.
member(S,U,C) -> maps:is_key(C,maps:get(U,maps:get(subscriptions,S),#{})).
push(Map,Key,Id) -> maps:put(Key,[Id|maps:get(Key,Map,[])],Map).
take_before(Ids,none,Limit) -> lists:sublist(Ids,Limit);
take_before(Ids,Before,Limit) when is_integer(Before),Before>0 ->
  lists:sublist(lists:dropwhile(fun(Id)->Id>=Before end,Ids),Limit);
take_before(_,_,_) -> [].
stats(S) ->
  #{users=>map_size(maps:get(users,S)),communities=>map_size(maps:get(communities,S)),
    posts=>map_size(maps:get(posts,S)),comments=>map_size(maps:get(comments,S)),messages=>map_size(maps:get(messages,S)),
    online=>length([ok || #{online:=true} <- maps:values(maps:get(users,S))]),
    memberships=>maps:map(fun(_,C)->map_size(maps:get(members,C)) end,maps:get(communities,S)),
    post_counts=>maps:map(fun(_,Ids)->length(Ids) end,maps:get(community_posts,S)),
    reposts=>maps:get(reposts,S),otp_release=>list_to_binary(erlang:system_info(otp_release))}.
