-- Update a session's tokens and user info after a refresh.
update sessions
set name = $2, email = $3, access_token = $4, refresh_token = $5, refreshed_at = now()
where id = $1
