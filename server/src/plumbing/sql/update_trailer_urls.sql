UPDATE hero_content
  SET trailer_url = $2, trailer_audio_url = $3
  WHERE id = $1;
