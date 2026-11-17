#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).
main(Args) ->
  Root=filename:dirname(filename:dirname(filename:absname(escript:script_name()))),
  ok=file:set_cwd(Root),
  %% Optional local OTP app overlay, useful when a system installation lacks crypto.
  case os:getenv("PROJECT4_CRYPTO_ROOT") of
    false->case filelib:is_file("build/runtime/crypto/ebin/crypto.app") of
      true->true=code:add_patha(filename:absname("build/runtime/crypto/ebin")); false->ok end;
    Overlay->true=code:add_patha(filename:join([Overlay,"ebin"]))
  end,
  ok=filelib:ensure_dir("build/ebin/placeholder"),
  true=code:add_patha(filename:absname("build/ebin")),
  lists:foreach(fun(P)->
    case compile:file(P,[debug_info,warnings_as_errors,report_errors,report_warnings,{outdir,"build/ebin"}]) of
      {ok,_}->ok; _->halt(1) end
  end,filelib:wildcard("src/*.erl")++filelib:wildcard("test/*.erl")),
  {ok,_}=file:copy("src/reddit.app.src","build/ebin/reddit.app"),
  try reddit_tools:main(Args)
  catch error:{tool_failed,N}->halt(N);
        C:R:S -> io:format(standard_error,"~p: ~p~n~p~n",[C,R,S]),halt(1) end.
