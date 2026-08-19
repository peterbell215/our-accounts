require 'rails_helper'

RSpec.describe "Manual forecasts", type: :request do
  let(:holidays) { create(:holidays_category) }
  let(:month) { Date.current.beginning_of_month }

  def submit(amount, category: holidays, on: month)
    post forecast_category_manual_path(category, month: on.to_fs(:iso8601)),
         params: { manual_forecast: { amount: amount } }
  end

  it "records a figure against the category and month" do
    expect { submit("850.00") }.to change(ManualForecast, :count).by(1)

    expect(ManualForecast.last).to have_attributes(category: holidays, month: month,
                                                   amount: Money.from_amount(850.00))
    expect(response).to redirect_to(forecast_category_path(holidays, month: month))
  end

  # The unique index is on (category, month), so a second submission has to find the first rather than
  # collide with it.
  it "changes the figure already there rather than adding a second" do
    submit("850.00")

    expect { submit("900.00") }.not_to change(ManualForecast, :count)
    expect(ManualForecast.last.amount).to eq(Money.from_amount(900.00))
  end

  # Emptying the field is how a prediction is withdrawn. Saving a blank as zero would be a different
  # statement — "nothing will be spent" rather than "I have not said".
  it "withdraws the prediction when the field is left empty" do
    submit("850.00")

    expect { submit("") }.to change(ManualForecast, :count).by(-1)
    expect(response).to redirect_to(forecast_category_path(holidays, month: month))
  end

  it "does nothing where there was no prediction to withdraw" do
    expect { submit("") }.not_to change(ManualForecast, :count)

    expect(response).to have_http_status(:redirect)
  end

  it "refuses a negative prediction and says why" do
    submit("-10.00")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prohibited this prediction from being saved")
    expect(ManualForecast.count).to be_zero
  end

  it "keeps a figure for one month separate from another" do
    submit("850.00")
    submit("100.00", on: month.next_month)

    expect(ManualForecast.count).to eq(2)
  end
end
