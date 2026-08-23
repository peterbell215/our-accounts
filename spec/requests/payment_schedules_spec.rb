require 'rails_helper'

RSpec.describe "Payment schedules", type: :request do
  let(:subscriptions) { create(:subscriptions_category) }
  let(:energy) { create(:counterparty, name: "Octopus Energy", account_number: "1") }

  # One row of the form: a payee, named the way the forecast groups it, and the choice made for it.
  def row(cadence, counterparty: energy, description: nil)
    { counterparty_id: counterparty&.id, description: description, cadence_months: cadence }
  end

  def submit(*rows, category: subscriptions)
    patch category_payment_schedules_path(category), params: { payment_schedules: rows }
  end

  it "records a frequency and returns to the category" do
    expect { submit(row(3)) }.to change(PaymentSchedule, :count).by(1)

    expect(PaymentSchedule.sole).to have_attributes(category: subscriptions, counterparty: energy,
                                                    cadence_months: 3)
    expect(response).to redirect_to(edit_category_path(subscriptions))
    expect(flash[:notice]).to eq("Payment frequencies saved.")
  end

  # The unique index is partial, on (category, counterparty) where the counterparty is present, so a
  # second submission has to find the first rather than collide with it.
  it "changes the frequency already set rather than adding a second" do
    submit(row(3))

    expect { submit(row(12)) }.not_to change(PaymentSchedule, :count)
    expect(PaymentSchedule.sole.cadence_months).to eq(12)
  end

  it "withdraws a ruling when the frequency goes back to working it out" do
    submit(row(3))

    expect { submit(row(PaymentSchedule::WORK_IT_OUT)) }.to change(PaymentSchedule, :count).by(-1)
  end

  it "stores a ruling with no frequency for a payee that is not a regular payment" do
    submit(row(PaymentSchedule::NOT_REGULAR))

    expect(PaymentSchedule.sole).to have_attributes(cadence_months: nil, counterparty: energy)
  end

  it "rules on a payee named by its description, having no counterparty" do
    submit(row(1, counterparty: nil, description: "ANCIENT STREAMING CO"))

    expect(PaymentSchedule.sole).to have_attributes(description: "ANCIENT STREAMING CO",
                                                    counterparty: nil)
  end

  it "rules on several payees in one submission" do
    water = create(:counterparty, name: "South Staffs Water", account_number: "2")

    expect { submit(row(1), row(3, counterparty: water)) }.to change(PaymentSchedule, :count).by(2)
  end

  describe "a request the form could not have made" do
    # The select offers four frequencies and two words, so anything else was hand-crafted.  Refusing the
    # whole submission rather than half-applying it, and saying so.
    it "applies nothing and reports the refusal" do
      expect { submit(row(3), row(7, counterparty: create(:counterparty, name: "Thames", account_number: "2"))) }
        .not_to change(PaymentSchedule, :count)

      expect(response).to redirect_to(edit_category_path(subscriptions))
      expect(flash[:alert]).to include("could not be saved")
    end

    # What `expect`'s doubled brackets are for: a hash arriving where an array of rows belongs.
    it "refuses a hash where the rows should be" do
      patch category_payment_schedules_path(subscriptions),
            params: { payment_schedules: { counterparty_id: energy.id, cadence_months: 1 } }

      expect(response).to have_http_status(:bad_request)
    end

    it "is a 404 for a category that does not exist" do
      patch category_payment_schedules_path(category_id: 0), params: { payment_schedules: [ row(1) ] }

      expect(response).to have_http_status(:not_found)
    end
  end
end
