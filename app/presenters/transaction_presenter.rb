class TransactionPresenter
  attr_reader :transaction, :view, :categories, :account

  def initialize(transaction, view, categories, account)
    @transaction = transaction
    @view = view
    @categories = categories
    @account = account
  end

  # Removed date method - handled by form builder in view

  # Removed category method - handled by form builder in view

  # Removed description method - handled by form builder in view

  # Keep amount for display formatting if needed elsewhere, or call helper directly
  # This version just formats the amount for display
  def amount
    view.humanized_money transaction.amount # Removed class logic, apply class in view
  end

  # Add other formatting methods if required, e.g., formatted_date
  def formatted_date
    transaction.date&.strftime("%d/%m/%Y")
  end
end
