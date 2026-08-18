module ApplicationHelper
  # Every date the reader sees goes through here, so they all read alike: 1-Jan-23.
  #
  # @param [Date, Time, nil] value
  # @return [String, nil]
  def short_date(value) = value&.to_fs(:short_date)
end
