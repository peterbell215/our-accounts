# A supplier or vendor the household deals with — Tesco, Octopus Energy, the water company.
#
# Not one of the household's own accounts, despite inheriting from Account.  Modelling a counterparty as an
# account is what lets Transaction#counterparty be an ordinary association, and leaves room for a future
# double-entry view where money leaves one account and arrives at another.  The cost is that AccountsController
# has to filter it out of the account list.
class Counterparty < Account
end
