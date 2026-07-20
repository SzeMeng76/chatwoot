class Email::ReplyToBuilder < Email::BaseBuilder
  pattr_initialize [:inbox!, :message!]

  def build
    reply_to = inbox.email? ? channel.email : account_support_email

    sender_name(reply_to)
  end
end
