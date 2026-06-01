class Evolution::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if processing_own_message?

    if processed_params.dig('key', 'fromMe')
      process_outgoing_message
    else
      process_incoming_message
    end
  rescue StandardError => e
    Rails.logger.error("[Evolution] Incoming message error: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
  end

  private

  def processed_params
    @processed_params ||= begin
      data = params['data'] || params[:data] || params
      data.is_a?(Hash) ? data.with_indifferent_access : {}.with_indifferent_access
    end
  end

  def processing_own_message?
    processed_params.dig('key', 'fromMe') == true
  end

  def process_outgoing_message
    Rails.logger.info("[Evolution] Outgoing message acknowledged: #{processed_params.dig('key', 'id')}")
  end

  def process_incoming_message
    return if duplicate_message?

    set_contact
    return unless @contact

    set_contact_inbox
    set_conversation
    create_message
  end

  def duplicate_message?
    source_id = processed_params.dig('key', 'id')
    return false if source_id.blank?

    @inbox.messages.find_by(source_id: source_id).present?
  end

  def set_contact
    remote_jid = processed_params.dig('key', 'remoteJid')
    return if remote_jid.blank?

    phone_number = extract_phone_number(remote_jid)
    return if phone_number.blank?

    push_name = processed_params['pushName'].presence || phone_number

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: phone_number,
      inbox: @inbox,
      contact_attributes: {
        name: push_name,
        phone_number: "+#{phone_number}"
      }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def set_contact_inbox
    return if @contact_inbox.present?

    @contact_inbox = ContactInbox.find_or_create_by!(
      contact_id: @contact.id,
      inbox_id: @inbox.id,
      source_id: extract_phone_number(processed_params.dig('key', 'remoteJid'))
    )
  end

  def set_conversation
    @conversation = @contact_inbox.conversations.where.not(status: :resolved).last
    return if @conversation

    @conversation = ::Conversation.create!(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: {}
    )
  end

  def create_message
    content = extract_message_content
    return if content.blank?

    @message = @conversation.messages.create!(
      content: content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: processed_params.dig('key', 'id')&.to_s
    )

    Rails.logger.info("[Evolution] Message created: #{@message.id} - #{content}")
  end

  def extract_message_content
    msg_type = processed_params['messageType']
    return processed_params.dig('message', 'conversation') if msg_type == 'conversation'
    return processed_params.dig('message', 'extendedTextMessage', 'text') if msg_type == 'extendedTextMessage'

    processed_params.dig('message', 'conversation') ||
      processed_params.dig('message', 'extendedTextMessage', 'text')
  end

  def extract_phone_number(remote_jid)
    return nil if remote_jid.blank?

    remote_jid.to_s.split('@').first.gsub(/\D/, '')
  end
end

Evolution::IncomingMessageService.prepend_mod_with('Evolution::IncomingMessageService')
