cd client && watchexec --restart --verbose --wrap-process=session --stop-signal SIGTERM --exts gleam --watch src/ -- "gleam run -m lustre/dev build --outdir=../server/priv/static"
