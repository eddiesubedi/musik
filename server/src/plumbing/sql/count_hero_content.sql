SELECT count(*)::int as total
  FROM hero_content
  WHERE media_type = $1;
