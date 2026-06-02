# == Schema Information
#
# Table name: channel_evolution
#
#  id                    :bigint           not null, primary key
#  account_id            :integer          not null
#  identifier            :string           not null
#  instance_name         :string           not null
#  instance_id           :string
#  webhook_url           :string
#  qr_code               :string
#  status                :string           default("pending")
#  additional_attributes :jsonb
#  phone_number          :string
#  session               :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_channel_evolution_on_identifier  (identifier) UNIQUE
#  index_channel_evolution_on_instance_id (instance_id)
#  index_channel_evolution_on_account_id (account_id)
#

class Channel::Evolution < ApplicationRecord
  include Channelable

  self.table_name = 'channel_evolution'

  EDITABLE_ATTRS = [
    :instance_name,
    :phone_number,
    { additional_attributes: {} }
  ].freeze

  has_secure_token :identifier

  validates :instance_name, presence: true, length: { maximum: 100 }
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }, if: -> { webhook_url.present? }
  validates :phone_number, presence: true, if: :connected?

  enum status: {
    pending: 'pending',
    connecting: 'connecting',
    connected: 'connected',
    disconnected: 'disconnected',
    error: 'error'
  }

  after_create_commit :setup_evolution_instance
  before_destroy :cleanup_evolution_instance

  def name
    'Evolution'
  end

  def medium
    :whatsapp
  end

  def active?
    return false if instance_id.blank?
    return false if status == 'disconnected'

    true
  end

  def connected?
    status == 'connected'
  end

  def inactive?
    !active?
  end

  def create_instance
    Evolution::ApiService.new(channel: self).create_instance
  end

  def setup_webhook(chatwoot_url)
    Evolution::WebhookSetupService.new(channel: self).perform
  end

  def fetch_qr_code
    Evolution::ApiService.new(channel: self).get_qr_code
  end

  def connection_status
    Evolution::ApiService.new(channel: self).check_connection_status
  end

  def process_webhook(params)
    event = params['event'] || params[:event]
    Rails.logger.info("[Evolution] Processing webhook event: #{event}")

    case event
    when 'messages.upsert', 'MESSAGES_UPSERT'
      Evolution::IncomingMessageService.new(inbox: inbox, params: params).perform
    when 'messages.update', 'MESSAGES_UPDATE'
      handle_message_status_update(params)
    when 'connection.update', 'CONNECTION_UPDATE'
      handle_connection_update(params)
    when 'send.message', 'SEND_MESSAGE'
      Rails.logger.info('[Evolution] Ignoring send.message event')
    else
      Rails.logger.info("[Evolution] Unhandled event: #{event}")
    end
  rescue StandardError => e
    Rails.logger.error("[Evolution] process_webhook failed: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end

  private

  def handle_message_status_update(params)
    data = params['data'] || params[:data] || {}
    key_id = data['keyId'] || data.dig('key', 'id')
    evolution_status = data['status']
    return if key_id.blank? || evolution_status.blank?
    Rails.logger.info "[Evolution] status update keyId=#{key_id} evolution_status=#{evolution_status}"

    new_status = map_evolution_status(evolution_status)
    return if new_status.blank?

    message = inbox.messages.find_by(source_id: key_id)
    if message.nil?
      Rails.logger.info "[Evolution] status update ignored, message not found source_id=#{key_id}"
      return
    end

    return if message.status.to_s == new_status.to_s

    previous_status = message.status
    message.status = new_status
    message.save!

    Rails.logger.info "[Evolution] message #{message.id} status #{previous_status} -> #{new_status}"
  rescue StandardError => e
    Rails.logger.error "[Evolution] handle_message_status_update failed: #{e.class} #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def map_evolution_status(evolution_status)
    case evolution_status.to_s.upcase
    when 'DELIVERY_ACK'   then 'delivered'
    when 'READ', 'PLAYED' then 'read'
    end
  end

  def handle_connection_update(params)
    data = params['data'] || params[:data] || {}
    state = data['state'] || data[:state]

    case state
    when 'open'
      update_columns(status: 'connected', updated_at: Time.current)
      Rails.logger.info("[Evolution] Channel #{id} state=open status=connected")

      wuid = data['wuid'] || data['instance']&.dig('user')&.dig('id') || data['user']&.dig('id')
      if wuid.present?
        phone = wuid.to_s.split('@').first.gsub(/\D/, '')
        if phone.present? && phone.match?(/\A\d{8,15}\z/)
          update_columns(phone_number: phone)
          Rails.logger.info("[Evolution] Channel #{id} phone_number=#{phone}")
        end
      end
    when 'close'
      update_columns(status: 'disconnected', updated_at: Time.current)
      Rails.logger.info("[Evolution] Channel #{id} state=close status=disconnected")
    when 'connecting'
      update_columns(status: 'connecting', updated_at: Time.current)
      Rails.logger.info("[Evolution] Channel #{id} state=connecting status=connecting")
    end
  end

  def setup_evolution_instance
    return if instance_id.present?

    Rails.logger.info("[Evolution] setup starting for instance_name=#{instance_name}")

    result = create_instance
    Rails.logger.info("[Evolution] create_instance result: #{result.inspect}")

    unless result[:success]
      handle_setup_failure("create_instance failed: #{result[:error].inspect}")
      return
    end

    reload

    if instance_id.blank?
      handle_setup_failure('instance_id missing after create (Evolution returned no id)')
      return
    end

    webhook_result = Evolution::WebhookSetupService.new(channel: self).perform
    Rails.logger.info("[Evolution] webhook setup result: #{webhook_result.inspect}")

    unless webhook_result[:success]
      handle_setup_failure("webhook setup failed: #{webhook_result[:error].inspect}")
      return
    end

    Rails.logger.info("[Evolution] setup completed successfully for #{instance_name}")
  rescue StandardError => e
    Rails.logger.error("[Evolution] setup_evolution_instance exception: #{e.class} #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    handle_setup_failure("unexpected exception: #{e.message}")
  end

  def handle_setup_failure(reason)
    Rails.logger.error("[Evolution] Setup FAILED for #{instance_name}: #{reason}")

    begin
      if instance_name.present?
        Evolution::ApiService.new(channel: self).delete_instance
        Rails.logger.info("[Evolution] cleaned up Evolution-side instance #{instance_name}")
      end
    rescue StandardError => e
      Rails.logger.warn("[Evolution] cleanup of Evolution-side instance failed: #{e.message}")
    end

    update_column(:status, 'error') if respond_to?(:status)

    if inbox.present?
      inbox_id_for_log = inbox.id
      begin
        inbox.destroy!
        Rails.logger.info("[Evolution] destroyed orphan inbox=#{inbox_id_for_log}")
      rescue StandardError => e
        Rails.logger.error("[Evolution] inbox.destroy failed: #{e.message}")
      end
    end
  end

  def cleanup_evolution_instance
    return if instance_name.blank?

    Rails.logger.info("[Evolution] cleaning up instance #{instance_name} before inbox destroy")
    result = Evolution::ApiService.new(channel: self).delete_instance
    Rails.logger.info("[Evolution] cleanup result: #{result.inspect}")
  rescue StandardError => e
    Rails.logger.warn("[Evolution] cleanup failed (continuing destroy): #{e.class} #{e.message}")
  end
end

Channel::Evolution.prepend_mod_with('Channel::Evolution')
