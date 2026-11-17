%% RSA-2048 / SHA-256 with PKCS#1 v1.5 signatures. Private keys never leave clients.
-module(reddit_crypto).
-include_lib("public_key/include/public_key.hrl").
-export([generate/1,valid_public/1,payload/1,sign/2,verify/3]).
generate(Dir) ->
  ok=filelib:ensure_dir(filename:join(Dir,"placeholder")),
  Private=public_key:generate_key({rsa,2048,65537}),
  Public=#'RSAPublicKey'{modulus=Private#'RSAPrivateKey'.modulus,publicExponent=Private#'RSAPrivateKey'.publicExponent},
  PrivPath=filename:join(Dir,"private.pem"),
  %% Exclusive creation prevents accidentally replacing an existing identity.
  {ok,F}=file:open(PrivPath,[write,binary,exclusive]),
  ok=file:change_mode(PrivPath,8#600),
  ok=file:write(F,public_key:pem_encode([public_key:pem_entry_encode('RSAPrivateKey',Private)])),
  ok=file:close(F),
  PubPath=filename:join(Dir,"public.pem"),
  ok=file:write_file(PubPath,public_key:pem_encode([public_key:pem_entry_encode('RSAPublicKey',Public)])),
  #{private_key=>list_to_binary(PrivPath),public_key=>list_to_binary(PubPath)}.
decode(Pem) -> [Entry]=public_key:pem_decode(Pem), public_key:pem_entry_decode(Entry).
valid_public(Pem) ->
  try decode(Pem) of
    #'RSAPublicKey'{modulus=N,publicExponent=E} -> N >= (1 bsl 2047) andalso N < (1 bsl 2048) andalso E=:=65537;
    _ -> false
  catch _:_ -> false end.
payload(P) ->
  O=case maps:get(original,P,none) of none->null; V->V end,
  iolist_to_binary(json:encode([1,maps:get(author,P),maps:get(community,P),maps:get(text,P),O])).
sign(P,PrivatePem) -> base64:encode(public_key:sign(payload(P),sha256,decode(PrivatePem))).
verify(P,Sig,Pem) ->
  try valid_public(Pem) andalso public_key:verify(payload(P),sha256,base64:decode(Sig),decode(Pem))
  catch _:_ -> false end.
