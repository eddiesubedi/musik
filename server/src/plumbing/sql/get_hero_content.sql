SELECT id, imdb_id, name, description, year, imdb_rating, genres, media_type, background, logo, poster
  FROM hero_content
  WHERE media_type = $1
  ORDER BY random()
  LIMIT $2;
