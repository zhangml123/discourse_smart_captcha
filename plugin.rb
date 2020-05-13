# name: discourse_smart_captcha
# about: Alibaba cloud smart captcha for Discourse
# version: 0.1
# authors: null
# url: https://github.com/zhangml123/discourse_smart_captcha.git

require 'net/http'
require 'uri'
require 'openssl'
require 'cgi'
enabled_site_setting :discourse_smart_captcha
after_initialize do

	require_dependency 'users_controller'

	class ::UsersController
	  	def create
	  		if SiteSetting.discourse_smart_captcha && !verifyCaptcha
		      return fail_with("login.verify_failed")
		    end
			params.require(:email)
		    params.require(:username)
		    params.require(:invite_code) if SiteSetting.require_invite_code
		    params.permit(:user_fields)

		    unless SiteSetting.allow_new_registrations
		      return fail_with("login.new_registrations_disabled")
		    end

		    if params[:password] && params[:password].length > User.max_password_length
		      return fail_with("login.password_too_long")
		    end

		    if params[:email].length > 254 + 1 + 253
		      return fail_with("login.email_too_long")
		    end

		    if SiteSetting.require_invite_code && SiteSetting.invite_code.strip.downcase != params[:invite_code].strip.downcase
		      return fail_with("login.wrong_invite_code")
		    end

		    if clashing_with_existing_route?(params[:username]) || User.reserved_username?(params[:username])
		      return fail_with("login.reserved_username")
		    end

		    params[:locale] ||= I18n.locale unless current_user

		    new_user_params = user_params.except(:timezone)

		    user = User.where(staged: true).with_email(new_user_params[:email].strip.downcase).first

		    if user
		      user.active = false
		      user.unstage!
		    end

		    user ||= User.new
		    user.attributes = new_user_params

		    # Handle API approval and
		    # auto approve users based on auto_approve_email_domains setting
		    if user.approved? || EmailValidator.can_auto_approve_user?(user.email)
		      ReviewableUser.set_approved_fields!(user, current_user)
		    end

		    # Handle custom fields
		    user_fields = UserField.all
		    if user_fields.present?
		      field_params = params[:user_fields] || {}
		      fields = user.custom_fields

		      user_fields.each do |f|
		        field_val = field_params[f.id.to_s]
		        if field_val.blank?
		          return fail_with("login.missing_user_field") if f.required?
		        else
		          fields["#{User::USER_FIELD_PREFIX}#{f.id}"] = field_val[0...UserField.max_length]
		        end
		      end

		      user.custom_fields = fields
		    end

		    authentication = UserAuthenticator.new(user, session)

		    if !authentication.has_authenticator? && !SiteSetting.enable_local_logins
		      return render body: nil, status: :forbidden
		    end

		    authentication.start

		    if authentication.email_valid? && !authentication.authenticated?
		      # posted email is different that the already validated one?
		      return fail_with('login.incorrect_username_email_or_password')
		    end

		    activation = UserActivator.new(user, request, session, cookies)
		    activation.start

		    # just assign a password if we have an authenticator and no password
		    # this is the case for Twitter
		    user.password = SecureRandom.hex if user.password.blank? && authentication.has_authenticator?

		    if user.save
		      authentication.finish
		      activation.finish
		      user.update_timezone_if_missing(params[:timezone])

		      secure_session[HONEYPOT_KEY] = nil
		      secure_session[CHALLENGE_KEY] = nil

		      # save user email in session, to show on account-created page
		      session["user_created_message"] = activation.message
		      session[SessionController::ACTIVATE_USER_KEY] = user.id

		      # If the user was created as active, they might need to be approved
		      user.create_reviewable if user.active?

		      render json: {
		        success: true,
		        active: user.active?,
		        message: activation.message,
		        user_id: user.id
		      }
		    elsif SiteSetting.hide_email_address_taken && user.errors[:primary_email]&.include?(I18n.t('errors.messages.taken'))
		      session["user_created_message"] = activation.success_message

		      if existing_user = User.find_by_email(user.primary_email&.email)
		        Jobs.enqueue(:critical_user_email, type: :account_exists, user_id: existing_user.id)
		      end

		      render json: {
		        success: true,
		        active: user.active?,
		        message: activation.success_message,
		        user_id: user.id
		      }
		    else
		      errors = user.errors.to_hash
		      errors[:email] = errors.delete(:primary_email) if errors[:primary_email]

		      render json: {
		        success: false,
		        message: I18n.t(
		          'login.errors',
		          errors: user.errors.full_messages.join("\n")
		        ),
		        errors: errors,
		        values: {
		          name: user.name,
		          username: user.username,
		          email: user.primary_email&.email
		        },
		        is_developer: UsernameCheckerService.is_developer?(user.email)
		      }
		    end
		  rescue ActiveRecord::StatementInvalid
		    render json: {
		      success: false,
		      message: I18n.t("login.something_already_taken")
		    }
		  end
		def verifyCaptcha
			access_secret = SiteSetting.access_secret
			param = {} 
			param["AccessKeyId"] = SiteSetting.access_key
			param["Action"]='AuthenticateSig'
			param["AppKey"] = SiteSetting.app_key
			param["Format"] = 'JSON'
			param["RegionId"] = 'cn-hangzhou'
			param["RemoteIp"] = SiteSetting.remote_ip
			param["Scene"] = 'ic_register'
			param["SessionId"] = params[:user_fields][:sessionId]
			param["Sig"] = params[:user_fields][:sig]
			param["SignatureMethod"] = 'HMAC-SHA1'
			param["SignatureNonce"] = Time.new.to_i.to_s + rand(9999).to_s
			param["SignatureVersion"] = '1.0'
			param["Timestamp"] = Time.now.strftime("%Y-%m-%dT%H:%M:%S")+"Z"
			param["Token"] = params[:user_fields][:token]
			param["Version"] = '2018-01-12'
			params_string = URI.encode_www_form(param)
			signature_string = 'POST&%2F&' + CGI.escape(params_string)
			hash1  = OpenSSL::HMAC.digest('sha1', access_secret+"&", signature_string)
			signature = Base64.encode64(hash1)
			param["Signature"] = signature.chomp
			uri=URI.parse("http://afs.aliyuncs.com")
			http=Net::HTTP.new(uri.host,uri.port)
			response=Net::HTTP.post_form(uri, param)
			
			if JSON.parse(response.body)["Code"] == 100
				puts JSON.parse(response.body)["Code"] 
				return true
			else
				puts JSON.parse(response.body)["Code"] 
				return false
			end
		end
	  	
	end
end

register_css <<EOF
    #SM_BTN_1 { width: 100%; margin: 0 auto; }
    #SM_BTN_WRAPPER_1 {    padding: 1em;}
    .login-form form table {width : 100% !important }
EOF