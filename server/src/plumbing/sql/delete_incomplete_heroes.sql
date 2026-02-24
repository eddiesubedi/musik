DELETE FROM hero_content
  WHERE name = ''
     OR description = ''
     OR year = ''
     OR imdb_rating = ''
     OR genres = ''
     OR background = ''
     OR logo = ''
     OR poster = '';
