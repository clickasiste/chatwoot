require 'base64'

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
    content, attachment_info = extract_message_payload
    return if content.blank? && attachment_info.nil?

    @message = @conversation.messages.build(
      content: content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: processed_params.dig('key', 'id')&.to_s
    )

    attach_media_to(@message, attachment_info) if attachment_info

    @message.save!
    Rails.logger.info("[Evolution] Message created: id=#{@message.id} content=#{content.to_s[0..40]} attachment=#{attachment_info ? attachment_info[:file_type] : 'none'}")
  rescue StandardError => e
    Rails.logger.error("[Evolution] create_message failed: #{e.class} #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end

  def extract_message_payload
    msg_type = processed_params['messageType'].to_s
    msg = processed_params['message'] || {}

    case msg_type
    when 'conversation'
      [msg['conversation'], nil]
    when 'extendedTextMessage'
      [msg.dig('extendedTextMessage', 'text'), nil]
    when 'imageMessage'
      data = msg['imageMessage'] || {}
      [data['caption'], build_attachment_info(data, 'image', 'image/jpeg')]
    when 'videoMessage'
      data = msg['videoMessage'] || {}
      [data['caption'], build_attachment_info(data, 'video', 'video/mp4')]
    when 'audioMessage'
      data = msg['audioMessage'] || {}
      [nil, build_attachment_info(data, 'audio', 'audio/ogg')]
    when 'documentMessage'
      data = msg['documentMessage'] || {}
      [data['caption'] || data['fileName'], build_attachment_info(data, 'file', 'application/octet-stream')]
    when 'stickerMessage'
      data = msg['stickerMessage'] || {}
      [nil, build_attachment_info(data, 'image', 'image/webp')]
    else
      [nil, nil]
    end
  end

  def build_attachment_info(data, file_type, default_mime)
    base64_data = data['base64'] || processed_params['base64']
    return nil if base64_data.blank?

    mime = data['mimetype'] || default_mime
    filename = data['fileName'].presence || generate_file_name(file_type, mime)

    {
      file_type: file_type,
      mime: mime,
      filename: filename,
      base64: base64_data
    }
  end

  def generate_file_name(file_type, mime)
    ext = case mime.to_s
          when 'image/jpeg' then 'jpg'
          when 'image/png' then 'png'
          when 'image/webp' then 'webp'
          when 'video/mp4' then 'mp4'
          when 'audio/ogg', 'audio/ogg; codecs=opus' then 'ogg'
          when 'audio/mpeg' then 'mp3'
          when 'application/pdf' then 'pdf'
          else 'bin'
          end
    "#{file_type}-#{Time.now.to_i}.#{ext}"
  end

  def attach_media_to(message, info)
    io = StringIO.new(Base64.strict_decode64(info[:base64]))
    message.attachments.new(
      account_id: message.account_id,
      file_type: info[:file_type]
    ).file.attach(
      io: io,
      filename: info[:filename],
      content_type: info[:mime]
    )
  end

  def extract_phone_number(remote_jid)
    return nil if remote_jid.blank?

    remote_jid.to_s.split('@').first.gsub(/\D/, '')
  end
end

Evolution::IncomingMessageService.prepend_mod_with('Evolution::IncomingMessageService')
