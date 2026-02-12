-module(dev_ffi).
-export([file_mtime/1, dir_max_mtime/1, run_cmd/1, is_dev/0]).

is_dev() ->
    case os:getenv("DEV") of
        false -> false;
        _ -> true
    end.

file_mtime(Path) ->
    case filelib:last_modified(Path) of
        0 -> 0;
        DateTime -> calendar:datetime_to_gregorian_seconds(DateTime)
    end.

dir_max_mtime(Dir) ->
    filelib:fold_files(binary_to_list(Dir), "\\.gleam$", true, fun(File, Acc) ->
        case filelib:last_modified(File) of
            0 -> Acc;
            DT -> max(calendar:datetime_to_gregorian_seconds(DT), Acc)
        end
    end, 0).

run_cmd(Cmd) ->
    os:cmd(binary_to_list(Cmd)),
    nil.
