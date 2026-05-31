class Evolution::WebhookSetupService
  pattr_initialize [:channel!]

  def perform
    return unless channel.instance_id.present?

    webhook_url = build_webhook_url
    response = HTTParty.post(
      "#{base_url}/webhook/set",
      headers: headers,
      body: webhook_payload(webhook_url).to_json
    )

    if response.success?
      Rails.logger.info("[Evolution] Webhook configured for instance: #{channel.instance_id}")
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

  def base_url
    ENV.fetch('EVOLUTION_API_URL', 'https://evo.clickasiste.com')
  end

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

  def webhook_payload(webhook_url)
    {
      instanceName: channel.instance_id,
      webhook: {
        url: webhook_url,
        byEvents: true,
        events: %w[
          QRCODE.UPDATED
          CONNECTION.UPDATE
          MESSAGES.UPSERT
          MESSAGES.UPDATE
          MESSAGES.DELETE
          SEND_MESSAGE
          CONTACTS.UPSERT
          CONTACTS_UPDATE
        ]
      }
    }
  end
end

Evolution::WebhookSetupService.prepend_mod_with('Evolution::WebhookSetupService')
