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
  validates :phone_number, presence: true, if: :active?

  enum status: {
    pending: 'pending',
    connecting: 'connecting',
    connected: 'connected',
    disconnected: 'disconnected',
    error: 'error'
  }

  after_create_commit :setup_evolution_instance

  def name
    'Evolution'
  end

  def medium
    :whatsapp
  end

  def active?
    status == 'connected' && instance_id.present?
  end

  def inactive?
    !active?
  end

  def create_instance
    Evolution::ApiService.new(self).create_instance
  end

  def setup_webhook(chatwoot_url)
    Evolution::WebhookSetupService.new(self).perform
  end

  def fetch_qr_code
    Evolution::ApiService.new(self).get_qr_code
  end

  def connection_status
    Evolution::ApiService.new(self).check_connection_status
  end

  def process_webhook(params)
    Evolution::IncomingMessageService.new(inbox: inbox, params: params).perform
  end

  private

  def setup_evolution_instance
    return if instance_id.present?

    create_instance
  end
end

Channel::Evolution.prepend_mod_with('Channel::Evolution')
