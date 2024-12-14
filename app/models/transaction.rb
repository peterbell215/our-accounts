class Transaction < ApplicationRecord
  belongs_to :creditor
  belongs_to :debitor
end
