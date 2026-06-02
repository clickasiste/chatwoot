class Evolution::SendMessageService
  pattr_initialize [:channel!, [:message!]]

  def perform(to:, body:, media_url: nil)
    return { success: false, error: 'Instance not connected' } unless channel.active?

    attachment = message&.attachments&.first

    if attachment.present?
      send_media(to, body, attachment)
    else
      send_text(to, body)
    end
  end

  private

  def send_text(to, body)
    endpoint = "#{base_url}/message/sendText/#{channel.instance_name}"
    payload = {
      number: normalize_phone_number(to),
      text: body.to_s
    }
    post(endpoint, payload)
  end

  def send_media(to, body, attachment)
    file_type = attachment.file_type.to_s

    if file_type == 'audio'
      send_audio(to, attachment)
    else
      send_media_generic(to, body, attachment)
    end
  end

  def send_audio(to, attachment)
    endpoint = "#{base_url}/message/sendWhatsAppAudio/#{channel.instance_name}"
    payload = {
      number: normalize_phone_number(to),
      audio: attachment.file_url
    }
    post(endpoint, payload)
  end

  def send_media_generic(to, body, attachment)
    endpoint = "#{base_url}/message/sendMedia/#{channel.instance_name}"
    payload = {
      number: normalize_phone_number(to),
      mediatype: map_media_type(attachment.file_type),
      mimetype: extract_mime_type(attachment),
      media: attachment.file_url,
      fileName: extract_file_name(attachment)
    }
    payload[:caption] = body if body.present? && attachment.file_type.to_s != 'file'
    post(endpoint, payload)
  end

  def post(endpoint, payload)
    response = HTTParty.post(endpoint, headers: headers, body: payload.to_json, timeout: 30)
    if response.success?
      data = response.parsed_response
      message_id = data.dig('key', 'id')
      Rails.logger.info("[Evolution] Message sent successfully: #{message_id}")
      update_message_external_id(message_id) if message.present?
      { success: true, message_id: message_id }
    else
      Rails.logger.error("[Evolution] Send failed: #{response.code} #{response.body}")
      { success: false, error: response.parsed_response }
    end
  rescue StandardError => e
    Rails.logger.error("[Evolution] Send exception: #{e.class} #{e.message}")
    { success: false, error: e.message }
  end

  def map_media_type(file_type)
    case file_type.to_s
    when 'image' then 'image'
    when 'video' then 'video'
    else 'document'
    end
  end

  def extract_mime_type(attachment)
    return attachment.file.content_type if attachment.respond_to?(:file) && attachment.file.respond_to?(:content_type) && attachment.file.content_type.present?
    return attachment.file.blob.content_type if attachment.respond_to?(:file) && attachment.file.respond_to?(:blob)

    case attachment.file_type.to_s
    when 'image' then 'image/jpeg'
    when 'video' then 'video/mp4'
    when 'audio' then 'audio/ogg'
    else 'application/octet-stream'
    end
  end

  def extract_file_name(attachment)
    return attachment.file.filename.to_s if attachment.respond_to?(:file) && attachment.file.respond_to?(:filename)
    return attachment.file_name if attachment.respond_to?(:file_name) && attachment.file_name.present?

    "file.#{attachment.file_type}"
  end

  def base_url
    ENV.fetch('EVOLUTION_API_URL', 'https://evo.clickasiste.com')
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'apikey' => ENV.fetch('EVOLUTION_API_KEY', nil)
    }
  end

  def normalize_phone_number(phone)
    phone.to_s.gsub(/[^\d]/, '')
  end

  def update_message_external_id(message_id)
    return unless message && message_id.present?

    message.update!(source_id: message_id, status: :sent)
  end
end

Evolution::SendMessageService.prepend_mod_with('Evolution::SendMessageService')
