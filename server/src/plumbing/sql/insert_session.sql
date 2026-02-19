-- Insert or update a session with tokens.
insert into sessions (id, name, email, access_token, refresh_token, refreshed_at)
values ($1, $2, $3, $4, $5, now())
on conflict (id) do update set name = $2, email = $3, access_token = $4, refresh_token = $5, refreshed_at = now()
