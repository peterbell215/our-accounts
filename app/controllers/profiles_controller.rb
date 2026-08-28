# Your own login: what it is, whether a second factor is on it, and the way to the two screens that
# change either.
#
# Deliberately no show_actions strip.  This is a report about you rather than a record — there is nothing
# here to Edit as a record and nothing to Destroy — so it follows the forecast screens rather than the
# five Show screens, and show_actions_spec.rb is right not to know about it.
class ProfilesController < ApplicationController
  def show
    @user = Current.user
  end
end
