module CounterpartiesHelper
  # One sortable column heading on the counterparties list.
  #
  # Clicking the column already sorted on reverses it; clicking any other switches to it, ascending.  The
  # arrow marks which column is in force, so the heading says what the order is rather than leaving the
  # reader to infer it from the rows.
  #
  # @param [String] column one of CounterpartiesController::SORTS
  # @param [String] label
  # @return [String]
  def counterparty_sort_link(column, label)
    current = @sort == column
    direction = current && @direction == "asc" ? "desc" : "asc"
    arrow = " #{@direction == 'asc' ? '▲' : '▼'}" if current

    link_to counterparties_path(sort: column, direction: direction) do
      safe_join([ label, arrow ].compact)
    end
  end
end
