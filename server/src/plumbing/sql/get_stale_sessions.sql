-- Get sessions that haven't been refreshed in over 1 hour.
select id, refresh_token
from sessions
where refreshed_at < now() - interval '1 hour'
