require 'httparty'
require 'base64'
require 'mini_magick'

class SpotifyClient
  SPOTIFY_API_URL = 'https://api.spotify.com/v1'
  MAX_IMAGE_FILE_SIZE = 256 * 1024
  MIN_IMAGE_QUALITY = 10

  def initialize(refresh_token)
    @refresh_token = refresh_token
    @access_token = refresh_access_token
    @user_id = get_spotify_user_id
  end

  def create_playlist(playlist_name, playlist_description = '')
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" },
      body: { name: playlist_name, description: playlist_description, public: true }.to_json
    }
    response = HTTParty.post("#{SPOTIFY_API_URL}/users/#{@user_id}/playlists", options)
    handle_response(response)['id']
  end

  def modify_playlist(playlist_id, name, description)
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" },
      body: { name: name, description: description }.to_json
    }
    response = HTTParty.put("#{SPOTIFY_API_URL}/playlists/#{playlist_id}", options)
    handle_response(response)
  end

  def search_playlists(search_string)
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}" },
      query: { limit: 50, offset: 0 }
    }
    response = HTTParty.get("#{SPOTIFY_API_URL}/users/#{@user_id}/playlists", options)
    playlist_id = find_playlist_id(handle_response(response)['items'], search_string)
    return playlist_id unless playlist_id.nil?

    while response.parsed_response['next']
      next_url = response.parsed_response['next']
      response = HTTParty.get(next_url, headers: { "Authorization" => "Bearer #{@access_token}" })
      playlist_id = find_playlist_id(handle_response(response)['items'], search_string)
      return playlist_id unless playlist_id.nil?
    end

    nil
  end

  def find_playlist_id(playlists, search_string)
    playlist = playlists.find { |p| p['name'].downcase.include?(search_string.downcase) }
    playlist['id'] if playlist
  end

  def search_tracks(track_name, artist_name)
    return if track_name.nil? || artist_name.nil?
    query = "#{track_name} artist:#{artist_name}"
    response = HTTParty.get("#{SPOTIFY_API_URL}/search", query: { type: 'track', limit: 1, q: query }, headers: { "Authorization" => "Bearer #{@access_token}" })
    handle_response(response)['tracks']['items'].first
  end

  def replace_playlist_tracks(playlist_id, track_uris)
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" },
      body: { uris: track_uris }.to_json
    }
    response = HTTParty.put("#{SPOTIFY_API_URL}/playlists/#{playlist_id}/tracks", options)
    handle_response(response)
  end

  def set_playlist_cover(playlist_id, url)
    jpg_data = png_to_jpg(url)
    return if jpg_data.nil?

    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "image/jpeg" },
      body: Base64.strict_encode64(jpg_data)
    }
    
    response = HTTParty.put("#{SPOTIFY_API_URL}/playlists/#{playlist_id}/images", options)

    raise "Failed to set playlist cover image" unless response.success?
  end

  private

  def handle_response(response)
    if response.success?
      response.parsed_response
    else
      raise "Spotify API request failed with status code #{response.code}: #{response.message}"
    end
  end

  def refresh_access_token
    options = {
      body: { grant_type: 'refresh_token', refresh_token: @refresh_token },
      headers: { "Authorization" => "Basic " + Base64.strict_encode64("#{ENV['SPOTIFY_CLIENT_ID']}:#{ENV['SPOTIFY_CLIENT_SECRET']}"), "Content-Type" => "application/x-www-form-urlencoded" }
    }
    response = HTTParty.post("https://accounts.spotify.com/api/token", options)
    handle_response(response)['access_token']
  end

  def get_spotify_user_id
    response = HTTParty.get("#{SPOTIFY_API_URL}/me", headers: { "Authorization" => "Bearer #{@access_token}" })
    handle_response(response)['id']
  end

  def png_to_jpg(image_url)
    response = HTTParty.get(image_url)
    if response.success?
      image_data = response.body
      image = MiniMagick::Image.read(image_data)
      image.format("jpeg")
      image.resize("640x640")
      quality = 80
      image.quality(quality)
      jpeg_data = image.to_blob

      # Reduce the quality until the file size is less than MAX_IMAGE_FILE_SIZE
      while jpeg_data.length > MAX_IMAGE_FILE_SIZE && quality > MIN_IMAGE_QUALITY
        quality -= 5
        image.quality(quality)
        jpeg_data = image.to_blob
      end

      jpeg_data
    else
      raise "Failed to fetch image: HTTP Status #{response.code}"
    end
  rescue => e
    raise "Failed to convert image: #{e.message}"
  end
end