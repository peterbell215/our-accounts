class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Below allow_browser deliberately, and not where the generator put it.  Declared first, the
  # authentication filter would run first, and a browser too old for this application would be sent to a
  # sign-in screen it also cannot render, instead of to the page that tells it to upgrade.
  include Authentication
end
