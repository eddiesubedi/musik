SELECT coalesce(
  extract(epoch FROM (now() - max(created_at))) / 60,
  999999
)::int AS age_minutes
FROM hero_content;
