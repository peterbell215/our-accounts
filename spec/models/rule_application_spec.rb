require 'rails_helper'

RSpec.describe RuleApplication, type: :model do
  let!(:lloyds) { create(:lloyds_account) }
  let!(:subscriptions) { create(:subscriptions_category) }
  let(:github) { Counterparty.find_by(name: "GitHub") || create(:counterparty, name: "GitHub") }

  # The rule a reader would write from any one of the four GITHUB INC. rows: literal, and tied to no
  # transaction type.
  let(:rule) do
    create(:import_matcher, account: lloyds, description: 'GITHUB INC.',
                            description_is_regex: false, trx_type: nil,
                            category: subscriptions, counterparty: github)
  end

  subject(:application) { described_class.new(matcher: rule) }

  # The subscription as it actually arrives: monthly, on the 12th.
  def github_rows(count = 4, account: lloyds, **attributes)
    Array.new(count) do |month|
      create(:github_subscription, account: account, date: Date.new(2024, 9, 12) + month.months, **attributes)
    end
  end

  describe 'claiming transactions already imported' do
    let!(:rows) { github_rows }

    it 'claims every one the rule matches' do
      expect(application.apply).to eq 4
    end

    it 'sets the rule, the category and the counterparty in one go' do
      application.apply

      rows.each do |row|
        row.reload
        expect(row.import_matcher_id).to eq rule.id
        expect(row.category_id).to eq subscriptions.id
        expect(row.counterparty_id).to eq github.id
      end
    end

    it 'reports the transactions it claimed' do
      application.apply

      expect(application.transactions.map(&:id)).to match_array rows.map(&:id)
    end

    it 'leaves the running balances and the day order alone, a rule having nothing to say about either' do
      before_apply = rows.map { |row| row.reload.attributes.slice("balance_pence", "day_index") }

      application.apply

      expect(rows.map { |row| row.reload.attributes.slice("balance_pence", "day_index") }).to eq before_apply
    end
  end

  describe 'what it will not touch' do
    it 'leaves a category somebody chose by hand, even where the rule matches the row' do
      travel = Category.find_by!(name: "Travel")
      by_hand = create(:github_subscription, account: lloyds, date: Date.new(2024, 9, 12), category: travel)

      expect(application.apply).to eq 0
      expect(by_hand.reload.category_id).to eq travel.id
      expect(by_hand.import_matcher_id).to be_nil
    end

    it 'leaves a transaction another rule already claimed' do
      other = create(:import_matcher, account: lloyds, description: 'GITHUB', description_is_regex: true,
                                      category: Category.find_by!(name: "Shopping"))
      claimed = create(:github_subscription, account: lloyds, date: Date.new(2024, 9, 12),
                                             import_matcher: other)

      expect(application.apply).to eq 0
      expect(claimed.reload.import_matcher_id).to eq other.id
    end

    it 'does not reach another account, a rule belonging to the account it was learned on' do
      barclaycard = create(:barclay_card_account)
      elsewhere = github_rows(1, account: barclaycard).first

      expect(application.apply).to eq 0
      expect(elsewhere.reload.category_id).to be_nil
    end

    it 'claims nothing, and says so, when no transaction matches' do
      create(:tesco_shop, account: lloyds, date: Date.new(2024, 9, 12))

      expect(application.apply).to eq 0
      expect(application.transactions).to be_empty
    end
  end

  describe 'what the rule itself says' do
    it 'honours a transaction type where the rule names one' do
      rule.update!(trx_type: 'DD')
      deb = github_rows(1).first

      expect(application.apply).to eq 0
      expect(deb.reload.category_id).to be_nil
    end

    it 'takes any transaction type where the rule leaves it blank' do
      github_rows(1)
      create(:github_subscription, account: lloyds, date: Date.new(2024, 10, 12), trx_type: 'DD')

      expect(application.apply).to eq 2
    end

    it 'matches a pattern anywhere in the description' do
      pattern = create(:import_matcher, account: lloyds, description: 'GITHUB', description_is_regex: true,
                                        category: subscriptions, counterparty: github)
      row = create(:github_subscription, account: lloyds, date: Date.new(2024, 9, 12),
                                         description: 'GITHUB INC. 4429')

      expect(described_class.new(matcher: pattern).apply).to eq 1
      expect(row.reload.category_id).to eq subscriptions.id
    end

    # Transaction#find_match assigns the rule's counterparty unconditionally, which is safe at import time
    # because the row has none to lose.  Applied backwards it is not: the counterparty may have been created
    # from this very row a moment ago.
    it 'leaves a counterparty the row already has where the rule names none' do
      rule.update!(counterparty: nil)
      row = create(:github_subscription, account: lloyds, date: Date.new(2024, 9, 12), counterparty: github)

      expect(application.apply).to eq 1
      expect(row.reload.counterparty_id).to eq github.id
      expect(row.category_id).to eq subscriptions.id
    end
  end

  # Two rules can share a description: one naming an amount, catching the exception (the Apple.com/BILL
  # £7.99 subscription among the film and music purchases against the same description), and one with no
  # amount condition, catching whatever the first one leaves.  #match is the only thing either rule's
  # RuleApplication run consults, so this only needs #apply exercised twice.
  describe 'an amount condition, shared with a default rule on the same description' do
    let(:travel) { Category.find_by!(name: "Travel") }

    let(:subscription_rule) do
      create(:import_matcher, account: lloyds, description: 'APPLE.COM/BILL', trx_type: nil,
                              amount_comparison: 'equal_to', amount: Money.from_amount(-7.99),
                              category: subscriptions)
    end

    let(:default_rule) do
      create(:import_matcher, account: lloyds, description: 'APPLE.COM/BILL', trx_type: nil,
                              category: travel)
    end

    def apple_row(amount)
      create(:transaction, account: lloyds, date: Date.new(2024, 9, 12), description: 'APPLE.COM/BILL',
                           amount: Money.from_amount(amount))
    end

    it 'takes only the amount it names, leaving other amounts against the same description uncategorised' do
      subscription_row = apple_row(-7.99)
      purchase_row = apple_row(-12.99)

      expect(described_class.new(matcher: subscription_rule).apply).to eq 1
      expect(subscription_row.reload.category_id).to eq subscriptions.id
      expect(purchase_row.reload.category_id).to be_nil
    end

    # Creating the specific rule before the default is what makes retroactive application split existing
    # rows correctly — the same order-dependence RuleApplication already has for a literal rule created
    # after a matching regex one.
    it 'splits existing rows correctly when the amount-specific rule is applied before the default' do
      subscription_row = apple_row(-7.99)
      purchase_row = apple_row(-12.99)

      described_class.new(matcher: subscription_rule).apply
      described_class.new(matcher: default_rule).apply

      expect(subscription_row.reload.category_id).to eq subscriptions.id
      expect(purchase_row.reload.category_id).to eq travel.id
    end

    it 'leaves the amount-specific rule nothing to claim when the default is applied first' do
      subscription_row = apple_row(-7.99)
      purchase_row = apple_row(-12.99)

      described_class.new(matcher: default_rule).apply
      described_class.new(matcher: subscription_rule).apply

      expect(subscription_row.reload.category_id).to eq travel.id
      expect(purchase_row.reload.category_id).to eq travel.id
    end
  end
end
