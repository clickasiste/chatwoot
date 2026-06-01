class Webhooks::EvolutionController < ActionController::API
  before_action :set_channel

  def process_payload
    return head :ok if @channel.blank?

    @channel.process_webhook(params.to_unsafe_hash)
    head :ok
  end

  private

  def set_channel
    instance_name = params[:instance_name] || params[:instance]
    @channel = Channel::Evolution.find_by(instance_name: instance_name)
    Rails.logger.warn("[Evolution Webhook] Channel not found for instance: #{instance_name}") if @channel.blank?
  end
end
