-- Look up a session by its ID.
select name, email
from sessions
where id = $1
