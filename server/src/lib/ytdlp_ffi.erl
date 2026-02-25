-module(ytdlp_ffi).
-export([extract_url/2, now_seconds/0]).

extract_url(VideoId, Format) ->
    Cmd = lists:flatten(io_lib:format(
        "yt-dlp -g -f ~s 'https://www.youtube.com/watch?v=~s' 2>/dev/null",
        [binary_to_list(Format), binary_to_list(VideoId)]
    )),
    Result = os:cmd(Cmd),
    Trimmed = string:trim(Result, both, "\n\r "),
    case Trimmed of
        [] -> {error, nil};
        _ -> {ok, list_to_binary(Trimmed)}
    end.

now_seconds() ->
    os:system_time(second).
