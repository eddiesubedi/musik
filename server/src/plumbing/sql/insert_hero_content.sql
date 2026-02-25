INSERT INTO hero_content (id, imdb_id, name, description, year, imdb_rating, genres, media_type, background, logo, poster, trailer_yt_id, trailer_url, trailer_audio_url)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
  ON CONFLICT (id) DO UPDATE SET
    background = EXCLUDED.background,
    logo = EXCLUDED.logo,
    poster = EXCLUDED.poster,
    trailer_yt_id = EXCLUDED.trailer_yt_id,
    trailer_url = EXCLUDED.trailer_url,
    trailer_audio_url = EXCLUDED.trailer_audio_url;
