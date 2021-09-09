require 'uri'
require 'net/http'

class TokenUrlsController < ApplicationController
  include Recaptcha::ClientHelper

  def new
    @notice = Notice.find(params[:id])

    authorize! :request_access_token, @notice

    @token_url = TokenUrl.new
  end

  def create
    # Remove everything between + and @
    token_url_params[:email].gsub!(/(\+.*?)(?=@)/, '')
    @token_url = TokenUrl.new(token_url_params)
    @notice = Notice.where(id: token_url_params[:notice_id]).first

    authorize!(:create_access_token, @notice) unless @notice.nil?

    valid_to_submit = validate

    if valid_to_submit[:status]
      @token_url[:expiration_date] = Time.now + LumenSetting.get_i('truncation_token_urls_active_period').seconds

      if @token_url.save
        run_post_create_actions
      else
        redirect_to(
          request_access_notice_path(@notice),
          alert: @token_url.errors.full_messages.join('<br>').html_safe
        )
      end
    else
      redirect_to(
        request_access_notice_path(@notice),
        alert: valid_to_submit[:why]
      )
    end
  end

  def run_post_create_actions
    TokenUrlsMailer.send_new_url_confirmation(
      token_url_params[:email], @token_url, @notice
    ).deliver_later

    redirect_to(
      request_access_notice_path(@notice),
      notice: 'A new single-use link has been generated and sent to ' \
              'your email address.'
    )
  end

  def generate_permanent
    @notice = Notice.find(params[:id])

    authorize! :generate_permanent_notice_token_urls, @notice

    @token_url = TokenUrl.new(
      user: current_user,
      email: current_user.email,
      valid_forever: true,
      notice: @notice
    )

    if @token_url.save
      redirect_to(
        notice_path(@notice),
        notice: 'A permanent URL for this notice has been created. ' \
                'You can view it below.'
      )
    else
      redirect_to(
        notice_path(@notice),
        alert: @token_url.errors.full_messages.join('<br>').html_safe
      )
    end
  end

  def disable_documents_notification
    token_url = TokenUrl.find_by_id(params[:id])
    errors = disable_documents_notification_errors(token_url)

    return redirect_to(root_path, alert: errors) if errors.present?

    token_url.update_attribute(:documents_notification, false)

    redirect_to(
      root_path,
      notice: 'Documents notification has been disabled.'
    )
  end

  private

  def token_url_params
    params.require(:token_url).permit(
      :email,
      :notice_id,
      :documents_notification
    )
  end

  def validate
    if @notice.nil?
      return {
        status: false,
        why: 'Notice not found.'
      }
    end

    unless verify_recaptcha(model: @token_url)
      return {
        status: false,
        why: 'Captcha verification failed, please try again.'
      }
    end

    if TokenUrl
       .where(email: token_url_params[:email])
       .where('expiration_date > ?', Time.now)
       .any?
      return {
        status: false,
        why: 'This email address has been used already. Use a different ' \
             'email, wait until the previous url expires or contact our ' \
             'team at team@lumendatabase.org to get a researcher account.'
      }
    end

    return {
      status: false,
      why: 'This email address is not valid. Try to use a different email ' \
           'address.'
    } if token_email_spam?(token_url_params[:email])

    { status: true }
  end

  def disable_documents_notification_errors(token_url)
    return 'Token url was not found.' if token_url.nil?
    return 'Wrong token provided.' unless token_url.token == params[:token]
  end

  def token_email_spam?(email)
    email_segments = email.split('@')[1].split('.')
    domain = "#{email_segments[email_segments.length - 2]}.#{email_segments[email_segments.length - 1]}"
    blocklisted_domains = ENV['TOKEN_URLS_BLOCKED_DOMAINS']&.split(',') || []

    return true if blocklisted_domains.include?(domain)

    begin
      uri = URI("http://us.stopforumspam.org/api?email=#{email}")
      res = Net::HTTP.get_response(uri)

      parsed_spam_response = Nokogiri::XML('<?xml version="1.0" encoding="utf-8"?>' + res.body)
      email_spam_frequency = parsed_spam_response.search('//frequency').text.to_i

      # If a frequency value is not 0 then it's spam
      !email_spam_frequency.zero?
    rescue
      # When the API is down just move along, not great but probably not going
      # to happen too often
      Rails.logger.warn 'Can\'t connect to the stopforumspam API.'
      true
    end
  end
end
