class MusicRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_request, only: [:activate, :destroy]
  skip_before_action :verify_authenticity_token, only: [:create]

  def index
    page = params[:page]&.to_i || 1
    @todays_playlists = current_user.todays_playlists
    @music_requests = current_user.music_requests.page(page).per(10)

    redirect_to tracks_path if @music_requests.empty? && page > 1
  end

  def activate
    @music_request.active!
    flash[:success] = 'This music request will be used for future playlists.'

    respond_to do |format|
      format.html { redirect_to music_requests_path }
    end
  end

  def create
    @music_request = MusicRequest.find_or_create_and_activate(current_user, music_request_params[:prompt])

    updates = current_user.process_todays_activities

    if updates
      flash[:success] = 'Generating today’s playlists. This may take a couple of minutes.'
    else
      flash[:warning] = 'You don’t have any new workouts on your calendar.'
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_notification }
      format.html { redirect_to root_path }
    end
  end

  def destroy
    if current_user.music_requests.count > 1
      @music_request.destroy
      flash[:success] = 'The music request has been deleted.'
    else
      flash[:warning] = 'You can’t delete your only music request.'
    end

    respond_to do |format|
      format.html { redirect_to music_requests_path }
    end
  end

  private

  def music_request_params
    params.require(:music_request).permit(:prompt)
  end

  def set_request
    @music_request = current_user.music_requests.find(params[:id])
  end
end
