FactoryBot.define do
  factory :category do
    name        { "Test Category" }
    description { "This is a test category." }

    # One category per forecast method, named after the kind of spending each method is for.
    #
    # Note the absence of a Utilities one, which is the obvious name for the regular-payments case:
    # rails_helper's REQUIRED_CATEGORIES already creates "Utilities" before the suite, and Category
    # validates its name unique, so such a factory would collide the first time it was used.
    factory :food_category do
      name        { "Food" }
      description { "Steady in total, unpredictable one shop at a time." }
    end

    factory :subscriptions_category do
      name            { "Subscriptions" }
      description     { "Direct debits and subscriptions, each on its own cadence." }
      forecast_method { :regular_payments }
    end

    factory :holidays_category do
      name            { "Holidays" }
      description     { "Too lumpy for any history to say anything about." }
      forecast_method { :manual }
    end

    factory :transfers_category do
      name            { "Transfers" }
      description     { "Money moved rather than money spent." }
      forecast_method { :excluded }
    end
  end
end
