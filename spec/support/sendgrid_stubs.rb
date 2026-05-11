# frozen_string_literal: true

module SendgridStubs
  SENDGRID_URL = "https://api.sendgrid.com/v3/mail/send"

  def stub_sendgrid_success
    stub_request(:post, SENDGRID_URL)
      .to_return(status: 202, body: "", headers: {})
  end

  def stub_sendgrid_error(status:)
    stub_request(:post, SENDGRID_URL)
      .to_return(status: status, body: "", headers: {})
  end
end

RSpec.configure do |config|
  config.include SendgridStubs
end
