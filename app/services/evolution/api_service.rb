class Evolution::ApiService
  pattr_initialize [:channel!]

  BASE_URL = "#{ENV.fetch('EVOLUTION_API_URL', 'https://evo.clickasiste.com')}/v2"

  def create_instance
    response = HTTParty.post(
      "#{BASE_URL}/instance/create",
      headers: headers,
      body: {
        instanceName: channel.instance_name,
        qrCode: true,
        integration: 'WHATSAPP-BAILEYS',
        webhookUrl: build_webhook_url,
        webhookByEvents: true,
        webhookEvents: %w[
          QRCODE.UPDATED
          CONNECTION.UPDATE
          MESSAGES.UPSERT
          MESSAGES.UPDATE
          MESSAGES.DELETE
          SEND_MESSAGE
          CONTACTS.UPSERT
          CONTACTS_UPDATE
        ].join(',')
      }.to_json
    )

    if response.success?
      data = response.parsed_response
      channel.update!(
        instance_id: data.dig('instance', 'instanceName'),
        status: 'connecting'
      )
      Rails.logger.info("[Evolution] Instance created: #{channel.instance_id}")
      { success: true, instance_id: channel.instance_id }
    else
      Rails.logger.error("[Evolution] Instance creation failed: #{response.body}")
      { success: false, error: response.parsed_response }
    end
  end

  def connect
    response = HTTParty.post(
      "#{BASE_URL}/instance/connect/#{channel.instance_id}",
      headers: headers,
      body: {}.to_json
    )

    if response.success?
      channel.update!(status: 'connecting')
      { success: true }
    else
      { success: false, error: response.parsed_response }
    end
  end

  def get_qr_code
    return { success: false, error: 'Instance not created' } unless channel.instance_id

    state_response = HTTParty.get(
      "#{BASE_URL}/instance/connectionState/#{channel.instance_id}",
      headers: headers
    )

    if state_response.success?
      state_data = state_response.parsed_response
      state = state_data.dig('state')

      case state
      when 'open'
        channel.update!(status: 'connected')
        return { success: true, status: 'connected', qr_code: nil }
      when 'close'
        channel.update!(status: 'disconnected')
        return { success: true, status: 'disconnected' }
      end
    end

    qr_response = HTTParty.get(
      "#{BASE_URL}/instance/qrcode/#{channel.instance_id}",
      headers: headers
    )

    if qr_response.success?
      qr_data = qr_response.parsed_response
      qr_base64 = qr_data.dig('qrcode', 'qrcode')

      channel.update!(qr_code: qr_base64, status: 'connecting')
      { success: true, status: 'connecting', qr_code: qr_base64 }
    else
      { success: false, error: qr_response.parsed_response }
    end
  end

  def check_connection_status
    return { success: false, error: 'Instance not created' } unless channel.instance_id

    response = HTTParty.get(
      "#{BASE_URL}/instance/connectionState/#{channel.instance_id}",
      headers: headers
    )

    if response.success?
      data = response.parsed_response
      state = data.dig('state')

      status_map = {
        'open' => 'connected',
        'close' => 'disconnected',
        'connecting' => 'connecting'
      }

      new_status = status_map[state] || 'error'
      channel.update!(status: new_status) if channel.status != new_status

      { success: true, status: new_status, state: state }
    else
      { success: false, error: response.parsed_response }
    end
  end

  def logout
    return { success: false, error: 'Instance not created' } unless channel.instance_id

    response = HTTParty.delete(
      "#{BASE_URL}/instance/logout/#{channel.instance_id}",
      headers: headers
    )

    if response.success?
      channel.update!(status: 'disconnected')
      { success: true }
    else
      { success: false, error: response.parsed_response }
    end
  end

  def delete_instance
    return { success: false, error: 'Instance not created' } unless channel.instance_id

    response = HTTParty.delete(
      "#{BASE_URL}/instance/delete/#{channel.instance_id}",
      headers: headers
    )

    if response.success?
      channel.update!(
        status: 'pending',
        instance_id: nil,
        qr_code: nil
      )
      { success: true }
    else
      { success: false, error: response.parsed_response }
    end
  end

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'apikey' => ENV.fetch('EVOLUTION_API_KEY', nil)
    }
  end

  def build_webhook_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    "#{frontend_url}/webhooks/evolution/#{channel.identifier}"
  end
end

Evolution::ApiService.prepend_mod_with('Evolution::ApiService')
