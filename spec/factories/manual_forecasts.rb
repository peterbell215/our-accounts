FactoryBot.define do
  factory :manual_forecast do
    category { Category.find_by(name: "Holidays") || FactoryBot.create(:holidays_category) }
    month    { Date.current.beginning_of_month }
    amount   { Money.from_amount(600.00) }
  end
end
