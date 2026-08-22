# Two date formats for the whole application, both registered here and both reached through a helper:
# 1-Jan-23 for a date, and March 2026 for a month the forecast is about.
#
# Dates were previously rendered three different ways — 01/01/2023 in the transaction list, an ISO date
# on the accounts index, and whatever the reader's browser locale produced for the rest, because a
# Stimulus controller rewrote them client-side. The same date read differently on two halves of one
# screen. Formatting on the server instead makes it one thing everywhere, at the cost of no longer
# following the reader's locale: this is a single-user application whose owner asked for this format.
#
# `%-d` is the day without a leading zero, so the width varies — the columns that hold dates are wide
# enough for that not to matter.
Date::DATE_FORMATS[:short_date] = "%-d-%b-%y"
Time::DATE_FORMATS[:short_date] = "%-d-%b-%y"

# The forecast is about a whole month rather than a day, and "1-Mar-26" would be claiming a precision it
# does not have. The rule being kept here was never "exactly one format" — it is that no view spells out
# a strftime of its own, so that changing how a date reads is a change in one place.
Date::DATE_FORMATS[:month_year] = "%B %Y"
