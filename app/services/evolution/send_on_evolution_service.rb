class Evolution::SendOnEvolutionService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Evolution
  end

  def perform_reply
    return if message.private?
    return unless outgoing_message?

    phone_number = message.conversation.contact_inbox.source_id
    body = message.outgoing_content
    media_url = message.attachments.first&.file_url

    result = Evolution::SendMessageService.new(
      channel: channel,
      message: message
    ).perform(
      to: phone_number,
      body: body,
      media_url: media_url
    )

    if result[:success]
      message.update!(source_id: result[:message_id], status: :sent) if result[:message_id].present?
    else
      Rails.logger.error("[Evolution] Send on Evolution failed: #{result[:error].inspect}")
      message.update!(status: :failed, external_error: result[:error].to_s.truncate(255))
    end
  rescue StandardError => e
    Rails.logger.error("[Evolution] SendOnEvolutionService error: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    message.update!(status: :failed, external_error: e.message.truncate(255))
  end

  def outgoing_message?
    message.outgoing? || message.template?
  end
end
