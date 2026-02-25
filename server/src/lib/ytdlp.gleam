@external(erlang, "ytdlp_ffi", "extract_url")
fn extract_url(video_id: String, format: String) -> Result(String, Nil)

/// Extract a direct video URL for a YouTube video using yt-dlp.
/// Blocking call — returns the URL or "" on failure.
pub fn extract(video_id: String, format: String) -> String {
  case extract_url(video_id, format) {
    Ok(url) -> url
    Error(_) -> ""
  }
}
