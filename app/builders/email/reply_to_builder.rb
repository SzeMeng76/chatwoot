class Email::ReplyToBuilder < Email::BaseBuilder
  pattr_initialize [:inbox!, :message!]

  def build
    reply_to = if inbox.email?
                 channel.email
               elsif fixed_reply_to_email.present?
                 parse_email(fixed_reply_to_email)
               elsif inbound_email_enabled?
                 "reply+#{conversation.uuid}@#{account.inbound_email_domain}"
               else
                 account_support_email
               end

    sender_name(reply_to)
  end

  private

  def inbound_email_enabled?
    account.feature_enabled?('inbound_emails') && account.inbound_email_domain.present?
  end

  # See the matching constant in ConversationReplyMailer#fixed_reply_to_email for context.
  def fixed_reply_to_email
    ENV['CONVERSATION_CONTINUITY_REPLY_TO_EMAIL']
  end
end
