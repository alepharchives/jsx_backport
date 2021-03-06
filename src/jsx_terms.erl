%% The MIT License

%% Copyright (c) 2010 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(jsx_terms).

-export([json_to_term/2, term_to_json/2]).

-include("../include/jsx_common.hrl").


-record(decoder_opts, {
    strict = false,
    encoding = auto,
    repeatable_keys = true
}).


-spec json_to_term(JSON::binary(), OptsList::decoder_opts()) ->
    jsx_term() | {jsx, incomplete, fun()}.

json_to_term(JSON, OptsList) ->
    Opts = parse_opts(OptsList, #decoder_opts{}),
    P = jsx:decoder([{encoding, Opts#decoder_opts.encoding}]),
    case Opts#decoder_opts.strict of
        true -> collect_strict(P(JSON), [[]], Opts)
        ; false -> collect(P(JSON), [[]], Opts)
    end.
    

%% the jsx formatter (pretty printer) can do most of the heavy lifting in 
%%   converting erlang terms to json strings

-record(encoder_opts, {
    strict = false,
    encoding = auto,
    formatter_opts = []
}).


-spec term_to_json(JSON::jsx_term(), OptsList::encoder_opts()) ->
    binary() | {jsx, incomplete, fun()}.

term_to_json(List, OptsList) ->
    Opts = parse_opts(OptsList, #encoder_opts{}),
    case Opts#encoder_opts.strict of
        true when is_list(List) -> continue
        ; true -> erlang:error(badarg)
        ; false -> continue
    end,
    case term_to_events(List) of
        L when is_tuple(L) ->
            jsx:format(L, Opts#encoder_opts.formatter_opts)
        ; L when is_list(L) ->
            jsx:format(lists:reverse(L), Opts#encoder_opts.formatter_opts)
    end.


parse_opts([{strict, Val}|Rest], Opts = #decoder_opts{})
        when Val =:= true; Val =:= false ->
    parse_opts(Rest, Opts#decoder_opts{strict = Val});
parse_opts([strict|Rest], Opts = #decoder_opts{}) ->
    parse_opts(Rest, Opts#decoder_opts{strict = true});
parse_opts([{strict, Val}|Rest], Opts = #encoder_opts{})
        when Val =:= true; Val =:= false ->
    parse_opts(Rest, Opts#encoder_opts{strict = Val});
parse_opts([strict|Rest], Opts = #encoder_opts{}) ->
    parse_opts(Rest, Opts#encoder_opts{strict = true});
parse_opts([{encoding, Val}|Rest], Opts = #decoder_opts{})
        when Val =:= auto; Val =:= utf8; 
            Val =:= utf16; Val =:= {utf16,little};
            Val =:= utf32; Val =:= {utf32,little} ->
    parse_opts(Rest, Opts#decoder_opts{encoding = Val});
parse_opts([encoding|Rest], Opts = #decoder_opts{}) ->
    parse_opts(Rest, Opts#decoder_opts{encoding = auto});
parse_opts([{encoding, Val}|Rest], Opts = #encoder_opts{})
        when Val =:= auto; Val =:= utf8; 
            Val =:= utf16; Val =:= {utf16,little};
            Val =:= utf32; Val =:= {utf32,little} ->
    parse_opts(Rest, Opts#encoder_opts{encoding = Val});
parse_opts([encoding|Rest], Opts = #encoder_opts{}) ->
    parse_opts(Rest, Opts#encoder_opts{encoding = auto});
parse_opts([{indent, Val}|Rest], Opts = #encoder_opts{formatter_opts = F})
        when is_integer(Val) ->
    parse_opts(Rest, Opts#encoder_opts{formatter_opts = [{indent, Val}] ++ F});
parse_opts([indent|Rest], Opts = #encoder_opts{formatter_opts = F}) ->
    parse_opts(Rest, Opts#encoder_opts{formatter_opts = [{indent, 1}] ++ F});
parse_opts([{space, Val}|Rest], Opts = #encoder_opts{formatter_opts = F})
        when is_integer(Val) ->
    parse_opts(Rest, Opts#encoder_opts{formatter_opts = [{space, Val}] ++ F});
parse_opts([space|Rest], Opts = #encoder_opts{formatter_opts = F}) ->
    parse_opts(Rest, Opts#encoder_opts{formatter_opts = [{space, 1}] ++ F});
parse_opts([{output_encoding, Val}|Rest], Opts = #encoder_opts{formatter_opts = F}) 
        when Val =:= utf8;
            Val =:= utf16; Val =:= {utf16,little};
            Val =:= utf32; Val =:= {utf32,little} ->
    parse_opts(Rest, Opts#encoder_opts{formatter_opts = [{output_encoding, Val}] ++ F});
parse_opts([{repeatable_keys, Val}|Rest], Opts = #decoder_opts{})
        when Val =:= true; Val =:= false ->
    parse_opts(Rest, Opts#decoder_opts{repeatable_keys = Val});
parse_opts([repeatable_keys|Rest], Opts = #decoder_opts{}) ->
    parse_opts(Rest, Opts#decoder_opts{repeatable_keys = true});
parse_opts([], Opts) ->
    Opts.


%% ensure the first jsx event we get is start_object or start_array when running
%%  in strict mode
collect_strict({jsx, [Start|Next], Next}, Acc, Opts) 
        when Start =:= start_object; Start =:= start_array ->
    collect(Next, [[]|Acc], Opts);
collect_strict(_, _, _) -> erlang:error(badarg).
    
    
%% collect decoder events and convert to eep0018 format 
collect({jsx, [Start|Next], _}, Acc, Opts) 
        when Start =:= start_object; Start =:= start_array ->
    collect(Next, [[]|Acc], Opts);
collect({jsx, [Event, end_json], _}, _, Opts) ->
    event(Event, Opts);
collect([Start|Next], Acc, Opts)
        when Start =:= start_object; Start =:= start_array ->
    collect(Next, [[]|Acc], Opts);
%% special case for empty object
collect([end_object|Next], [[], Parent|Rest], Opts)  when is_list(Parent) ->
    collect(Next, [[[{}]] ++ Parent] ++ Rest, Opts);
%% reverse the array/object accumulator before prepending it to it's parent
collect([end_object|Next], [Current, Parent|Rest], Opts) 
        when is_list(Parent) ->
    collect(Next, [[lists:reverse(Current)] ++ Parent] ++ Rest, Opts);
collect([end_array|Next], [Current, Parent|Rest], Opts) 
        when is_list(Parent) ->
    collect(Next, [[lists:reverse(Current)] ++ Parent] ++ Rest, Opts);
%% special case for empty object
collect([end_object|Next], [[], Key, Parent|Rest], Opts) ->
    collect(Next, [[{Key, [{}]}] ++ Parent] ++ Rest, Opts);
collect([End|Next], [Current, Key, Parent|Rest], Opts)
        when End =:= end_object; End =:= end_array ->
    collect(Next, [[{Key, lists:reverse(Current)}] ++ Parent] ++ Rest, Opts);      
collect([end_json], [[Acc]], _Opts) ->
    Acc;  
%% key can only be emitted inside of a json object, so just insert it directly 
%%   into the head of the accumulator and deal with it when we receive it's 
%%   paired value
collect([{key, _} = PreKey|Next], Acc, Opts) ->
    Key = event(PreKey, Opts),
    collect(Next, [Key] ++ Acc, Opts);
%% if our returned event is {jsx, incomplete, ...} try to force end and return 
%%   the Event if one is returned, else just return {incomplete, More/1}
collect({jsx, incomplete, More}, _Acc, Opts) ->
    case More(end_stream) of
        {jsx, [Event, end_json], _Next} -> event(Event, Opts)
        ; _ -> {incomplete, More}
    end;
%% check acc to see if we're inside an object or an array. because inside an 
%%   object context the events that fall this far are always preceded by a key 
%%   (which are binaries or atoms), if Current is a list, we're inside an array, 
%%   else, an object
collect([Event|Next], [Current|Rest], Opts) when is_list(Current) ->
    collect(Next, [[event(Event, Opts)] ++ Current] ++ Rest, Opts);
%% delete any prior uses of current key
collect([Event|Next], [Key, Current|Rest], Opts=#decoder_opts{repeatable_keys=false}) ->
    case proplists:is_defined(Key, Current) of
        true ->
            Acc = proplists:delete(Key, Current), 
            collect(Next,
                [[{Key, event(Event, Opts)}] ++ Acc] ++ Rest,
                Opts
            )
        ; _ ->
            collect(Next,
                [[{Key, event(Event, Opts)}] ++ Current] ++ Rest,
                Opts
            )
    end;
collect([Event|Next], [Key, Current|Rest], Opts) ->
    collect(Next, [[{Key, event(Event, Opts)}] ++ Current] ++ Rest, Opts);
%% any other event is an error
collect(_, _, _) -> erlang:error(badarg).
    

%% helper functions for converting jsx events to term format 
event({string, String}, _Opts) -> unicode:characters_to_binary(String);
event({key, Key}, _Opts) -> unicode:characters_to_binary(Key);
event({integer, Integer}, _Opts) -> Integer;
event({float, Float}, _Opts) -> Float;
event({literal, Literal}, _Opts) -> Literal.


%% convert term format representation to jsx events. note special casing for the 
%%   empty object
term_to_events([{}]) ->
    [end_object, start_object];
term_to_events([First|_] = List) when is_tuple(First) ->
    proplist_to_events(List, [start_object]);
term_to_events(List) when is_list(List) ->
    list_to_events(List, [start_array]);
term_to_events(Term) ->
    [Res] = term_to_event(Term),
    Res.


proplist_to_events([{Key, Term}|Rest], Acc) ->
    Event = term_to_event(Term),
    EncodedKey = key_to_event(Key),
    proplist_to_events(Rest, Event ++ EncodedKey ++ Acc);
proplist_to_events([], Acc) ->
    [end_object] ++ Acc;
proplist_to_events(_, _) ->
    erlang:error(badarg).


list_to_events([Term|Rest], Acc) ->
    list_to_events(Rest, term_to_event(Term) ++ Acc);
list_to_events([], Acc) ->
    [end_array] ++ Acc.


term_to_event(List) when is_list(List) ->
    term_to_events(List);
term_to_event(Float) when is_float(Float) ->
    [{float, Float}];
term_to_event(Integer) when is_integer(Integer) ->
    [{integer, Integer}];
term_to_event(String) when is_binary(String) -> 
    [{string, json_escape(String)}];
term_to_event(true) -> [{literal, true}];
term_to_event(false) -> [{literal, false}];
term_to_event(null) -> [{literal, null}];
term_to_event(_) -> erlang:error(badarg).


key_to_event(Key) when is_binary(Key) ->
    [{key, json_escape(Key)}].


%% json string escaping, for utf8 binaries. escape the json control sequences to 
%%  their json equivalent, escape other control characters to \uXXXX sequences, 
%%  everything else should be a legal json string component
json_escape(String) ->
    json_escape(String, <<>>).

%% double quote    
json_escape(<<$\", Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $\">>);
%% backslash \ reverse solidus
json_escape(<<$\\, Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $\\>>);
%% backspace
json_escape(<<$\b, Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $b>>);
%% form feed
json_escape(<<$\f, Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $f>>);
%% newline
json_escape(<<$\n, Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $n>>);
%% cr
json_escape(<<$\r, Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $r>>);
%% tab
json_escape(<<$\t, Rest/binary>>, Acc) -> 
    json_escape(Rest, <<Acc/binary, $\\, $t>>);
%% other control characters
json_escape(<<C/utf8, Rest/binary>>, Acc) when C >= 0, C < $\s -> 
    json_escape(Rest, <<Acc/binary, (json_escape_sequence(C))/binary>>);
%% escape u+2028 and u+2029 to avoid problems with jsonp
json_escape(<<C/utf8, Rest/binary>>, Acc) when C == 16#2028; C == 16#2029 ->
    json_escape(Rest, <<Acc/binary, (json_escape_sequence(C))/binary>>);
%% any other legal codepoint
json_escape(<<C/utf8, Rest/binary>>, Acc) ->
    json_escape(Rest, <<Acc/binary, C/utf8>>);
json_escape(<<>>, Acc) ->
    Acc;
json_escape(_, _) ->
    erlang:error(badarg).


%% convert a codepoint to it's \uXXXX equiv.
json_escape_sequence(X) ->
    <<A:4, B:4, C:4, D:4>> = <<X:16>>,
    <<$\\, $u, (to_hex(A)), (to_hex(B)), (to_hex(C)), (to_hex(D))>>.


to_hex(15) -> $f;
to_hex(14) -> $e;
to_hex(13) -> $d;
to_hex(12) -> $c;
to_hex(11) -> $b;
to_hex(10) -> $a;
to_hex(X) -> X + $0.



%% eunit tests
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

decode_test_() ->
    [
        {"empty object", ?_assert(json_to_term(<<"{}">>, []) =:= [{}])},
        {"empty array", ?_assert(json_to_term(<<"[]">>, []) =:= [])},
        {"simple object", 
            ?_assert(json_to_term(
                <<"{\"a\": true, \"b\": true, \"c\": true}">>, []
                ) =:= [{<<"a">>, true}, {<<"b">>, true}, {<<"c">>, true}]
            )
        },
        {"simple array", 
            ?_assert(json_to_term(<<"[true,true,true]">>, 
                    []
                ) =:= [true, true, true]
            )
        },
        {"nested structures", 
            ?_assert(json_to_term(
                    <<"{\"x\":[{\"x\":[{}, {}],\"y\":{}}, []],\"y\":{}}">>, []
                ) =:= [{<<"x">>, 
                            [[{<<"x">>, [[{}], [{}]]}, {<<"y">>, [{}]}],[]]},
                        {<<"y">>, [{}]}
                ]
            )
        },
        {"numbers", 
            ?_assert(json_to_term(
                    <<"[-100000000.0, -1, 0.0, 0, 1, 100000000, 10000000.0]">>, 
                    []
                ) =:= [-100000000.0, -1, 0.0, 0, 1, 100000000, 10000000.0]
            )
        },
        {"strings", 
            ?_assert(json_to_term(<<"[\"a string\"]">>, 
                []
            ) =:= [<<"a string">>])
        },
        {"literals", 
            ?_assert(json_to_term(<<"[true,false,null]">>, 
                    []
                ) =:= [true,false,null]
            )
        },
        {"naked true", 
            ?_assert(json_to_term(<<"true">>, []) =:= true)
        },
        {"naked short number", 
            ?_assert(json_to_term(<<"1">>, []) =:= 1)
        },
        {"naked float", ?_assert(json_to_term(<<"1.0">>, []) =:= 1.0)},
        {"naked string", 
            ?_assert(json_to_term(<<"\"hello world\"">>, 
                    []
                ) =:= <<"hello world">>
            )
        },
        {"strict mode", ?_assertError(badarg, json_to_term(<<"1.0">>,
                [{strict, true}]
            )
        )}
    ].
    
encode_test_() ->
    [
        {"empty object", ?_assert(term_to_json([{}], []) =:= <<"{}">>)},
        {"empty array", ?_assert(term_to_json([], []) =:= <<"[]">>)},
        {"simple object", 
            ?_assert(term_to_json([{<<"a">>, true}, {<<"b">>, true}], 
                    []
                ) =:= <<"{\"a\":true,\"b\":true}">>
            )
        },
        {"simple array", 
            ?_assert(term_to_json([true, true, true], 
                    []
                ) =:= <<"[true,true,true]">>
            )
        },
        {"nested structures", 
            ?_assert(term_to_json(
                    [{<<"x">>, 
                            [[{<<"x">>, [[{}], [{}]]}, {<<"y">>, [{}]}],[]]},
                        {<<"y">>, [{}]}], 
                    []
                ) =:= <<"{\"x\":[{\"x\":[{},{}],\"y\":{}},[]],\"y\":{}}">>
            )
        },
        {"numbers", 
            ?_assert(term_to_json(
                    [-10000000000.0, -1, 0.0, 0, 1, 10000000, 1000000000.0], 
                    []
                ) =:= <<"[-1.0e10,-1,0.0,0,1,10000000,1.0e9]">>
            )
        },
        {"strings", 
            ?_assert(term_to_json([<<"a string">>], 
                    []
                ) =:= <<"[\"a string\"]">>
            )
        },
        {"literals", 
            ?_assert(term_to_json([true,false,null],
                    []
                ) =:= <<"[true,false,null]">>
            )
        },
        {"naked true", 
            ?_assert(term_to_json(true, []) =:= <<"true">>)
        },
        {"naked number", 
            ?_assert(term_to_json(1, []) =:= <<"1">>)
        },
        {"float", ?_assert(term_to_json(1.0, []) =:= <<"1.0">>)},
        {"naked string", 
            ?_assert(term_to_json(<<"hello world">>, []) 
                =:= <<"\"hello world\"">>
            )
        },
        {"strict mode", ?_assertError(badarg, term_to_json(true,
                [{strict, true}]
            )
        )}
    ].

repeated_keys_test_() ->
    [
        {"simple repeated key",
            ?_assert(json_to_term(<<"{\"a\":false,\"a\":true}">>, [{repeatable_keys, false}])
                =:= [{<<"a">>, true}]
            )
        },
        {"nested repeated key",
            ?_assert(json_to_term(
                    <<"[{\"a\":false,\"a\":true},{\"a\":false,\"a\":true}]">>,
                [{repeatable_keys, false}])
                =:= [[{<<"a">>, true}], [{<<"a">>, true}]]
            )
        },
        {"multiple keys",
            ?_assert(json_to_term(<<"{\"a\":4,\"a\":3,\"a\":2,\"a\":1}">>, [{repeatable_keys, false}])
                =:= [{<<"a">>, 1}]
            )
        }
    ].

escape_test_() ->
    [
        {"json string escaping", 
            ?_assert(json_escape(
                    <<"\"\\\b\f\n\r\t">>
                ) =:= <<"\\\"\\\\\\b\\f\\n\\r\\t">>
            )
        },
        {"json string hex escape", 
            ?_assert(json_escape(
                    <<1, 2, 3, 11, 26, 30, 31>>
                ) =:= <<"\\u0001\\u0002\\u0003\\u000b\\u001a\\u001e\\u001f">>
            )
        },
        {"jsonp protection",
            ?_assert(json_escape(
                    <<226, 128, 168, 226, 128, 169>>
                ) =:= <<"\\u2028\\u2029">>
            )
        }
    ].

-endif.