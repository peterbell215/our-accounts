module ApplicationHelper
  # Every date the reader sees goes through here, so they all read alike: 1-Jan-23.
  #
  # @param [Date, Time, nil] value
  # @return [String, nil]
  def short_date(value) = value&.to_fs(:short_date)

  # One sortable column heading, for any list that sorts.
  #
  # Clicking the column already sorted on reverses it; clicking any other switches to it, ascending.  The
  # arrow marks which column is in force, so the heading says what the order is rather than leaving the
  # reader to infer it from the rows.
  #
  # The link is built with `url_for` and nothing but the two parameters, so it returns to the list it was
  # rendered on: a heading does not need telling which page it is on.  It reads `@sort` and `@direction`,
  # which every controller offering a sortable list sets.
  #
  # @param [String] column one of the controller's own whitelisted sorts
  # @param [String] label
  # @return [String]
  def sort_link(column, label)
    current = @sort == column
    direction = current && @direction == "asc" ? "desc" : "asc"
    arrow = " #{@direction == 'asc' ? '▲' : '▼'}" if current

    link_to url_for(sort: column, direction: direction) do
      safe_join([ label, arrow ].compact)
    end
  end
end
