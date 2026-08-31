module ImportMatchersHelper
  AMOUNT_COMPARISON_LABELS = {
    "equal_to" => "equal to",
    "not_equal_to" => "not equal to",
    "less_than" => "less than",
    "less_than_or_equal_to" => "less than or equal to",
    "greater_than" => "greater than",
    "greater_than_or_equal_to" => "greater than or equal to"
  }.freeze

  AMOUNT_COMPARISON_SYMBOLS = {
    "equal_to" => "=",
    "not_equal_to" => "≠",
    "less_than" => "<",
    "less_than_or_equal_to" => "≤",
    "greater_than" => ">",
    "greater_than_or_equal_to" => "≥"
  }.freeze

  # The <select> options for an amount condition, in the same order ImportMatcher::AMOUNT_COMPARISONS lists
  # them, with "any amount" left to include_blank.
  def amount_comparison_options
    ImportMatcher::AMOUNT_COMPARISONS.map { |value| [ AMOUNT_COMPARISON_LABELS.fetch(value), value ] }
  end

  # How a rule's amount condition reads on the index and show screens, e.g. "= -£7.99" or "any amount".
  def amount_condition_description(import_matcher)
    return "any amount" if import_matcher.amount_comparison.nil?

    "#{AMOUNT_COMPARISON_SYMBOLS.fetch(import_matcher.amount_comparison)} #{humanized_money_with_symbol(import_matcher.amount)}"
  end
end
