module TransactionsHelper
  # Where to ask for the page after this one, or nil at the end of the account's history.  `rows` asks
  # for a bare fragment rather than a redirect back to the account page.
  #
  # @param [Account] account
  # @param [TransactionPage] page
  # @return [String, nil]
  def transactions_next_page_url(account, page)
    return nil unless page.more?

    cursor = page.next_cursor

    account_transactions_path(account, rows: 1, as_of: page.anchor,
                                       before_date: cursor[:date],
                                       before_day_index: cursor[:day_index],
                                       before_id: cursor[:id])
  end

  # One button in the date navigation.  A step that cannot move the window — because the anchor is
  # already clamped to the end of the account's history — renders as a disabled button rather than a
  # link, so the controls keep their positions.
  #
  # @param [String] label
  # @param [Account] account
  # @param [TransactionPage] page
  # @param [Symbol] direction :back or :forward
  # @param [Symbol] unit :day, :week or :month
  # @return [String]
  def transaction_anchor_link(label, account, page, direction, unit)
    target = page.public_send(direction, unit)
    stuck = direction == :back ? page.at_earliest? : page.at_latest?

    if stuck || target.nil? || target == page.anchor
      tag.span label, class: "pure-button pure-button-disabled", aria: { disabled: true }
    else
      # Note `as_of` rather than `anchor`: Rails reserves `anchor:` in URL helpers for the fragment
      # identifier, so an `anchor:` option would produce "/accounts/1#2024-06-05" and never reach params.
      link_to label, account_path(account, as_of: target), class: "pure-button"
    end
  end
end
