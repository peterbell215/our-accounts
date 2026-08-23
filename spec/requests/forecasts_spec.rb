require 'rails_helper'

RSpec.describe "Forecasts", type: :request do
  let!(:data) { ForecastDataBuilder.new(today: Date.current).build }

  describe "GET /forecast" do
    it "shows this month by default, where this month has transactions in it" do
      get forecast_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Forecast for #{Date.current.to_fs(:month_year)}")
    end

    # Statements are imported in arrears, so for most of a month the current one holds nothing, and
    # opening there would show predictions with no actuals to weigh them against.
    it "opens on the last month with transactions rather than the calendar's" do
      Transaction.where(date: Date.current.beginning_of_month..).delete_all

      get forecast_path

      expect(response.body).to include("Forecast for #{(Date.current << 1).to_fs(:month_year)}")
    end

    it "shows the month asked for" do
      get forecast_path(month: "2026-03")

      expect(response.body).to include("Forecast for March 2026")
    end

    it "reads a full date as the month it falls in" do
      get forecast_path(month: "2026-03-17")

      expect(response.body).to include("Forecast for March 2026")
    end

    # A mistyped query string should show the reader a page, not a 500.
    it "falls back to the month it opens on rather than failing on a month it cannot read" do
      get forecast_path(month: "banana")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Forecast for #{Date.current.to_fs(:month_year)}")
    end

    it "falls back to the month it opens on when the parameter is empty" do
      get forecast_path(month: "")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Forecast for #{Date.current.to_fs(:month_year)}")
    end

    # Held to the same bounds the buttons show, so a hand-edited URL cannot strand the reader.
    it "clamps a month before the records begin" do
      get forecast_path(month: "1999-01")

      expect(response.body).to include("Forecast for #{Transaction.minimum(:date).to_fs(:month_year)}")
    end

    it "clamps a month beyond the year ahead it will forecast" do
      get forecast_path(month: (Date.current >> 60).to_fs(:iso8601))

      expect(response.body).to include("Forecast for #{(Date.current >> 12).to_fs(:month_year)}")
    end

    it "names every category and the uncategorised line" do
      get forecast_path

      expect(response.body).to include("Food", "Subscriptions", "Holidays", "Uncategorised")
    end

    it "lists an excluded category as not forecast, and out of the total" do
      get forecast_path

      expect(response.body).to include("Not forecast")
      expect(response.body).to include("Left out of the total deliberately")
    end

    # "£0.00" would claim a prediction of nothing had been made on purpose.
    it "says a hand-forecast category has no figure rather than showing zero" do
      get forecast_path

      expect(response.body).to include("not set")
      expect(response.body).to include("no figure for this month")
    end

    it "shows the difference instead of what is still to come, for a month that has finished" do
      get forecast_path(month: (Date.current << 2).to_fs(:iso8601))

      expect(response.body).to include("Difference")
      expect(response.body).not_to include("Still to come</th>")
    end
  end

  describe "GET /forecast/categories/:id" do
    it "shows the months an averaged category is averaged over" do
      get forecast_category_path(data.food, month: Date.current.to_fs(:iso8601))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The months it is averaged over")
    end

    it "shows the individual payments behind a category made of them" do
      get forecast_category_path(data.subscriptions, month: Date.current.to_fs(:iso8601))

      expect(response.body).to include("The payments it is made up of", "Octopus Energy", "South Staffs Water")
    end

    # Two charges from one payee inside a single month used to be drawn as one charge for their total,
    # dated the earlier of the two — on the page, a bill that had doubled rather than two ordinary ones.
    it "shows each occurrence where a payment has gone out twice in the month" do
      last_month = 1.month.ago.beginning_of_month
      create(:transaction, account: data.account, category: data.subscriptions, counterparty: data.energy,
                           date: last_month.change(day: 5), description: "OCTOPUS ENERGY",
                           trx_type: "DD", amount: Money.from_amount(-218.85))

      get forecast_category_path(data.subscriptions, month: last_month.strftime("%Y-%m"))

      expect(response.body).to include("#{last_month.change(day: 5).to_fs(:short_date)}, £218.85")
      expect(response.body).to include("#{last_month.change(day: 19).to_fs(:short_date)}, £218.85")
    end

    it "offers a form on a category forecast by hand" do
      get forecast_category_path(data.holidays, month: Date.current.to_fs(:iso8601))

      expect(response.body).to include("Your prediction", "Save prediction")
    end

    it "explains why an excluded category is left out" do
      get forecast_category_path(data.transfers, month: Date.current.to_fs(:iso8601))

      expect(response.body).to include("Not forecast", "count the same money twice")
    end

    it "is a 404 for a category that does not exist" do
      get forecast_category_path(id: 0)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /forecast/uncategorised" do
    it "shows the workings for everything with no category" do
      get forecast_uncategorised_path(month: Date.current.to_fs(:iso8601))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Uncategorised in", "The months it is averaged over")
    end
  end
end
