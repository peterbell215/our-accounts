# One date format for the whole application: 1-Jan-23.
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
