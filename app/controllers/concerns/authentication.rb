module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    # A redirect is right for a page the reader asked for, and wrong for anything fetched in the
    # background.  The transaction list pages itself with `get(..., responseKind: "html")`: a 302 is
    # followed by fetch transparently, so the list would receive the sign-in page as a 200, find no rows
    # in it, and quietly decide it had reached the end of the history.
    #
    # 401 with the sign-in URL in WWW-Authenticate is the convention @rails/request.js already
    # understands — its FetchRequest sends the browser there itself — so the reader lands on the sign-in
    # screen rather than on a list that has silently stopped, and no JavaScript here has to know about it.
    # It also writes no return_to, which is correct: a fragment of rows is not somewhere to come back to.
    def request_authentication
      if background_request?
        response.set_header("WWW-Authenticate", new_session_url)
        head :unauthorized
      else
        session[:return_to_after_authenticating] = request.url
        redirect_to new_session_path
      end
    end

    def background_request?
      request.xhr? || request.format.turbo_stream?
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
