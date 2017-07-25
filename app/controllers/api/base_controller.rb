class Api::BaseController < ApplicationController

  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_user!

  # rescue_from Exception do |exception| # https://github.com/bbatsov/ruby-style-guide#no-blind-rescues
  rescue_from StandardError do |exception|
    status = :internal_server_error
    error_hash = { error: I18n.t("api.errors.server_error"), details: {} }

    # That's why we are using string versions
    # http://stackoverflow.com/questions/14785817/why-are-ruby-cases-not-working-with-classes
    case exception.class.name
    when "Mongoid::Errors::Validations"
      status = :unprocessable_entity
      error_hash[:error] = (exception.try(:record).try(:errors).try(:full_messages) || []).join(", ") || I18n.t("api.errors.data.invalid")
      error_hash[:details] = (exception.try(:record).try(:errors) || {})
    when "Mongoid::Errors::DocumentNotFound"
      status = :not_found
      error_hash[:error] = I18n.t("api.errors.data.not_found")
    when "ActionController::ParameterMissing", "ApiError"
      status = :unprocessable_entity
      error_hash[:error] = exception.message
    when "AASM::InvalidTransition"
      status = :unprocessable_entity
      error_hash[:error] = I18n.t("api.errors.data.invalid_transition",
        state_attr_name: exception.object.class.human_attribute_name(:state).downcase,
        current_state_name: exception.originating_state.to_s,
        event_name: exception.event_name.to_s)
    end

    render status: status, json: error_hash, layout: false
  end

  def render_json_with(resource, options={})
    status = options[:status] || :ok
    serializer = options[:serializer] || (self.class.name.gsub("Controller","").singularize + "Serializer").constantize
    serializer_type = if options[:serializer_type].present?
      options[:serializer_type]
    elsif resource.kind_of?(Enumerable)
      :each_serializer
    else
      :serializer
    end
    render_options = {
      json: resource,
      status: status
    }
    render_options[serializer_type] = serializer
    render render_options
  end

  protected

    def current_user
      @current_user
    end

    def find_user_by_token
      authenticate_with_http_token do |token, options|
        @current_user = User.find_by(api_token: token)
      end
      @current_user
    end

    def authenticate_user!
      find_user_by_token || render_unauthorized
    end

    def render_unauthorized(realm = "Application")
      self.headers["WWW-Authenticate"] = %(Token realm="#{realm.gsub(/"/, "")}")
      render json: { error: I18n.t("api.errors.bad_credentials") }, status: :unauthorized
    end

end
