class Api::V1::Accounts::EvolutionController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_evolution_channel

  def get_qr_code
    result = Evolution::ApiService.new(@inbox.channel).get_qr_code

    if result[:success]
      render json: {
        qr_code: result[:qr_code],
        status: result[:status]
      }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def connection_status
    result = Evolution::ApiService.new(@inbox.channel).check_connection_status

    if result[:success]
      render json: {
        status: result[:status],
        state: result[:state]
      }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def reconnect
    result = Evolution::ApiService.new(@inbox.channel).connect

    if result[:success]
      render json: { message: 'Connection initiated' }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def disconnect
    result = Evolution::ApiService.new(@inbox.channel).logout

    if result[:success]
      render json: { message: 'Disconnected successfully' }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def delete_instance
    result = Evolution::ApiService.new(@inbox.channel).delete_instance

    if result[:success]
      render json: { message: 'Instance deleted successfully' }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def ensure_evolution_channel
    return if @inbox.evolution?

    render json: { error: 'Inbox is not an Evolution channel' }, status: :unprocessable_entity
  end
end

Api::V1::Accounts::EvolutionController.prepend_mod_with('Api::V1::Accounts::EvolutionController')
