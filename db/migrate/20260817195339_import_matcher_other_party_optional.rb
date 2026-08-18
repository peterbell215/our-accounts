# A rule's job is to assign a category; naming the counterparty is a bonus.  While other_party_id was
# NOT NULL every rule had to invent a TradingAccount, which is why AnalysisImporter names them after raw
# statement text and why a description too short to be a name lost its rule altogether.  Transactions have
# always allowed a null other_party, for the one-off or unidentifiable vendor; rules now match.
class ImportMatcherOtherPartyOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :import_matchers, :other_party_id, true
  end
end
