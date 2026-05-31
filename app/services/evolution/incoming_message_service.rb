class Evolution::IncomingMessageService
  include ::Whatsapp::IncomingMessageServiceHelpers
  include ::Whatsapp::IncomingMessageIdentifierHelper

  pattr_initialize [:inbox!, :params!]

  def perform
    return if processing_own_message?

    processed_params

    if processed_params[:typeWebhook].present?
      process_status_update
    elsif processed_params[:key]&.[]('fromMe')
      process_outgoing_message
    else
      process_incoming_message
    end
  rescue StandardError => e
    Rails.logger.error("[Evolution] Incoming message error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end

  private

  def processed_params
    @processed_params ||= params.is_a?(Hash) ? params : {}
  end

  def processing_own_message?
    processed_params[:key]&.[]('fromMe') == true
  end

  def process_status_update
    status = processed_params[:status]
    return if status.blank?

    external_id = processed_params.dig(:key, :id)
    return if external_id.blank?

    message = find_message_by_source_id(external_id)
    return unless message

    message.status = map_evolution_status(status)
    message.save!
  rescue StandardError => e
    Rails.logger.error("[Evolution] Status update error: #{e.message}")
  end

  def process_outgoing_message
    Rails.logger.info("[Evolution] Outgoing message acknowledged: #{processed_params.dig(:key, :id)}")
  end

  def process_incoming_message
    return if duplicate_message?

    set_contact
    return unless @contact

    ActiveRecord::Base.transaction do
      set_conversation
      create_message
    end
  end

  def duplicate_message?
    source_id = processed_params.dig(:key, :id)
    return false if source_id.blank?

    find_message_by_source_id(source_id).present?
  end

  def set_contact
    phone_number = processed_params.dig(:key, :remote)
    return if phone_number.blank?

    phone_number = normalize_phone_number(phone_number)

    @contact = @inbox.account.contacts.where(
      phone_number: phone_number
    ).first_or_create!(name: phone_number)
  end

  def set_conversation
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end

    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def create_message
    message_params = {
      content: extract_message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: processed_params.dig(:key, :id)&.to_s,
      content_attributes: {
        in_reply_to_external_id: processed_params.dig(:messageInfo, :quotedMessageRowId)
      }.compact
    }

    @message = @conversation.messages.create!(message_params)

    attach_media if processed_params[:message] && processed_params.dig(:message, :mediaUrl).present?
  end

  def extract_message_content
    return processed_params.dig(:message, :conversation) if processed_params[:messageType] == 'conversation'
    return processed_params.dig(:message, :extendedTextMessage, :text) if processed_params[:messageType] == 'extendedTextMessage'

    nil
  end

  def attach_media
    media_url = processed_params.dig(:message, :mediaUrl)
    media_type = processed_params.dig(:message, :mimetype)&.split('/')&.first || 'document'

    @message.attachments.new(
      account_id: @message.account_id,
      file_type: media_type,
      external_url: media_url
    )
    @message.save!
  end

  def normalize_phone_number(phone)
    phone = phone.to_s.gsub(/[^\d]/, '')
    phone.start_with?('0') ? "+57#{phone}" : (phone.start_with?('57') ? "+#{phone}" : phone)
  end

  def map_evolution_status(status)
    case status
    when 'DELIVERED' then 'delivered'
    when 'READ' then 'read'
    when 'ERROR' then 'failed'
    else status.downcase
    end
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end
end

Evolution::IncomingMessageService.prepend_mod_with('Evolution::IncomingMessageService')
