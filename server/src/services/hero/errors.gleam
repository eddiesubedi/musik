import lib/cinemeta/errors as cinemeta_errors
import lib/reelgood/errors as reelgood_errors

pub type HeroError {
  ReelgoodErr(reelgood_errors.ReelgoodError)
  CinemetaErr(cinemeta_errors.CinemetaErrors)
  FanartErr(Nil)
  NoImages(String)
  MissingData(String)
}
