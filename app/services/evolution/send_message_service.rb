class Evolution::SendMessageService
  pattr_initialize [:channel!, [:message!]]

  def perform(to:, body:, media_url: nil)
    return { success: false, error: 'Instance not connected' } unless channel.active?

    payload = build_payload(to, body, media_url)

    response = HTTParty.post(
      "#{base_url}/message/sendText/#{channel.instance_id}",
      headers: headers,
      body: payload.to_json
    )

    if response.success?
      data = response.parsed_response
      message_id = data.dig('key', 'id')

      Rails.logger.info("[Evolution] Message sent successfully: #{message_id}")

      update_message_external_id(message_id) if message.present?

      { success: true, message_id: message_id }
    else
      Rails.logger.error("[Evolution] Send failed: #{response.body}")
      { success: false, error: response.parsed_response }
    end
  end

  private

  def base_url
    "#{ENV.fetch('EVOLUTION_API_URL', 'https://evo.clickasiste.com')}/instance"
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'apikey' => ENV.fetch('EVOLUTION_API_KEY', nil)
    }
  end

  def build_payload(to, body, media_url)
    payload = {
      number: normalize_phone_number(to),
      text: body
    }

    payload[:mediaUrl] = media_url if media_url.present?

    payload
  end

  def normalize_phone_number(phone)
    phone = phone.to_s.gsub(/[^\d]/, '')
    phone.start_with?('0') ? "+57#{phone}" : (phone.start_with?('57') ? "+#{phone}" : phone)
  end

  def update_message_external_id(message_id)
    return unless message

    message.update!(
      source_id: message_id,
      status: :sent
    )
  end
end

Evolution::SendMessageService.prepend_mod_with('Evolution::SendMessageService')
