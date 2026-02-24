INSERT INTO hero_content (id, imdb_id, name, description, year, imdb_rating, genres, media_type, background, logo, poster)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
  ON CONFLICT (id) DO UPDATE SET
    background = EXCLUDED.background,
    logo = EXCLUDED.logo,
    poster = EXCLUDED.poster;
