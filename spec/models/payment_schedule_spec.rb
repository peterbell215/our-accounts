require 'rails_helper'

describe PaymentSchedule, type: :model do
  let(:subscriptions) { create(:subscriptions_category) }
  let(:energy) { create(:counterparty, name: "Octopus Energy", account_number: "1") }

  describe 'naming a payee' do
    it 'accepts a counterparty' do
      expect(build(:payment_schedule, category: subscriptions, counterparty: energy)).to be_valid
    end

    it 'accepts a description, for a payee that never acquired a counterparty' do
      expect(build(:payment_schedule, category: subscriptions, description: "ANCIENT STREAMING CO"))
        .to be_valid
    end

    it 'refuses both at once, which would be two names for one payee' do
      schedule = build(:payment_schedule, category: subscriptions, counterparty: energy,
                                          description: "OCTOPUS ENERGY")

      expect(schedule).not_to be_valid
    end

    it 'refuses neither, which would be a ruling on nothing' do
      expect(build(:payment_schedule, category: subscriptions)).not_to be_valid
    end

    # Blank is not a payee, but the partial unique index treats it as present while the validation treats
    # it as absent — so a "" would be a row neither guard can see.
    it 'normalises a blank description to nothing, so it is refused rather than stored' do
      schedule = build(:payment_schedule, category: subscriptions, description: "  ")

      expect(schedule).not_to be_valid
      expect(schedule.description).to be_nil
    end
  end

  describe 'the frequency' do
    it 'accepts each of the cadences a payment is really on' do
      Forecast::CADENCE_LABELS.each_key do |months|
        expect(build(:payment_schedule, category: subscriptions, counterparty: energy,
                                        cadence_months: months)).to be_valid
      end
    end

    # Null on a row that exists is how "not a regular payment" is stored — the third state, the absence
    # of a row being the first.
    it 'accepts nothing at all, meaning it is not a regular payment' do
      schedule = build(:payment_schedule, category: subscriptions, counterparty: energy, cadence_months: nil)

      expect(schedule).to be_valid
      expect(schedule).not_to be_regular
    end

    # Not cosmetic: the detector does `silence % cadence`, so zero raises and seven invents a schedule
    # nothing is on.
    it 'refuses a number of months no payment is on' do
      [ 0, 2, 7, -1 ].each do |months|
        expect(build(:payment_schedule, category: subscriptions, counterparty: energy,
                                        cadence_months: months)).not_to be_valid
      end
    end
  end

  describe 'one ruling per payee per category' do
    # The trap the two partial indexes exist for: SQLite treats NULLs as distinct, so a single unique
    # index over all three columns would let this through, both rows having a null description.
    it 'refuses a second ruling on the same counterparty' do
      create(:payment_schedule, category: subscriptions, counterparty: energy, cadence_months: 1)
      second = build(:payment_schedule, category: subscriptions, counterparty: energy, cadence_months: 3)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'refuses a second ruling on the same description' do
      create(:payment_schedule, category: subscriptions, description: "ODD JOB", cadence_months: 1)
      second = build(:payment_schedule, category: subscriptions, description: "ODD JOB", cadence_months: 3)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same payee in another category, which is a separate question' do
      create(:payment_schedule, category: subscriptions, counterparty: energy, cadence_months: 1)
      other = build(:payment_schedule, category: create(:food_category), counterparty: energy,
                                       cadence_months: 3)

      expect(other).to be_valid
    end
  end

  describe 'what it belongs to' do
    it 'goes with the category, being a statement about how that category behaves' do
      create(:payment_schedule, category: subscriptions, counterparty: energy)

      expect { subscriptions.destroy! }.to change(described_class, :count).by(-1)
    end

    # :destroy rather than :nullify, unlike a counterparty's transactions and rules: a nullified
    # counterparty_id with no description would leave a row that identifies nothing.
    it 'goes with the counterparty, rather than being left naming nobody' do
      create(:payment_schedule, category: subscriptions, counterparty: energy)

      expect { energy.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe '.apply' do
    def rows(cadence, counterparty_id: energy.id, description: nil)
      [ { counterparty_id: counterparty_id.to_s, description: description,
          cadence_months: cadence.to_s } ]
    end

    it 'records a frequency' do
      described_class.apply(category: subscriptions, rows: rows(3))

      expect(described_class.sole).to have_attributes(counterparty_id: energy.id, cadence_months: 3)
    end

    it 'changes a frequency rather than adding a second' do
      described_class.apply(category: subscriptions, rows: rows(3))
      described_class.apply(category: subscriptions, rows: rows(12))

      expect(described_class.sole.cadence_months).to eq(12)
    end

    # The same gesture that withdraws the hand-entered figure on the forecast, and the same meaning: "I
    # have not said" is a different statement from "never".
    it 'withdraws a ruling when the frequency is left blank' do
      described_class.apply(category: subscriptions, rows: rows(3))
      described_class.apply(category: subscriptions, rows: rows(described_class::WORK_IT_OUT))

      expect(described_class.count).to be_zero
    end

    it 'stores a ruling with no frequency for "not a regular payment"' do
      described_class.apply(category: subscriptions, rows: rows(described_class::NOT_REGULAR))

      expect(described_class.sole).to have_attributes(cadence_months: nil, counterparty_id: energy.id)
    end

    it 'rules on a payee named by description' do
      described_class.apply(category: subscriptions,
                            rows: rows(1, counterparty_id: nil, description: "ODD JOB"))

      expect(described_class.sole).to have_attributes(description: "ODD JOB", counterparty_id: nil)
    end

    it 'ignores a row naming no payee at all' do
      described_class.apply(category: subscriptions, rows: rows(1, counterparty_id: nil))

      expect(described_class.count).to be_zero
    end

    # All or nothing, so a forged value cannot leave half a screen applied.
    it 'applies nothing at all when any row is refused' do
      other = create(:counterparty, name: "Thames Water", account_number: "2")
      submitted = rows(3) + rows(7, counterparty_id: other.id)

      expect { described_class.apply(category: subscriptions, rows: submitted) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(described_class.count).to be_zero
    end
  end
end
