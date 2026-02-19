-- Delete a session by its ID.
delete from sessions
where id = $1
