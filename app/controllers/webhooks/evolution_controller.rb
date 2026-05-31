class Webhooks::EvolutionController < ActionController::API
  before_action :set_channel

  def process_payload
    return head :ok if @channel.blank?

    @channel.process_webhook(params.to_unsafe_hash)
    head :ok
  end

  private

  def set_channel
    @channel = Channel::Evolution.find_by(identifier: params[:instanceName])
  end
end
