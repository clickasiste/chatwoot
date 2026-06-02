class Evolution::WebhookSetupService
  pattr_initialize [:channel!]

  BASE_URL = ENV.fetch('EVOLUTION_API_URL', 'https://evo.clickasiste.com')

  def perform
    response = HTTParty.post(
      "#{BASE_URL}/webhook/set/#{channel.instance_name}",
      headers: headers,
      body: webhook_payload.to_json
    )

    if response.success?
      Rails.logger.info("[Evolution] Webhook configured for #{channel.instance_name}")
      { success: true }
    else
      Rails.logger.error("[Evolution] Webhook setup failed: #{response.body}")
      { success: false, error: response.parsed_response }
    end
  end

  def remove_webhook
    return unless channel.instance_id.present?

    response = HTTParty.delete(
      "#{base_url}/webhook/remove/#{channel.instance_id}",
      headers: headers
    )

    if response.success?
      Rails.logger.info("[Evolution] Webhook removed for instance: #{channel.instance_id}")
      { success: true }
    else
      Rails.logger.error("[Evolution] Webhook removal failed: #{response.body}")
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

  def webhook_payload
    {
      webhook: {
        enabled: true,
        url: "#{ENV.fetch('FRONTEND_URL')}/webhooks/evolution/#{channel.instance_name}",
        byEvents: false,
        base64: true,
        events: %w[
          QRCODE_UPDATED
          CONNECTION_UPDATE
          MESSAGES_UPSERT
          MESSAGES_UPDATE
          MESSAGES_DELETE
          SEND_MESSAGE
          CONTACTS_UPSERT
          CONTACTS_UPDATE
        ]
      }
    }
  end
end

Evolution::WebhookSetupService.prepend_mod_with('Evolution::WebhookSetupService')
