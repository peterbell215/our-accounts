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

  # The strip of buttons every Show screen opens with, so Back, Edit and Destroy are in the same place
  # and read the same whatever record is on show.  Anything particular to the model goes in the block,
  # and lands between Edit and Destroy.
  #
  # Destroy sits at the far end of the strip, apart from the rest, and always confirms: it is the one
  # button here that cannot be undone, so it should not fall under the cursor on the way to Edit.  What
  # the confirmation says is the screen's to write, because what is lost differs — an account takes its
  # transactions with it, a counterparty leaves them behind.
  #
  # @param [String] back path of the list this record belongs to
  # @param [String] edit path of the record's edit form
  # @param [String] destroy path the DELETE goes to
  # @param [String] confirm what the confirmation asks before the record goes
  # @yield model-specific buttons, rendered between Edit and Destroy
  # @return [String]
  def show_actions(back:, edit:, destroy:, confirm:, &block)
    render "layouts/show_actions", back: back, edit: edit, destroy: destroy, confirm: confirm,
                                  model_actions: (capture(&block) if block)
  end
end
