# app/controllers/transactions_controller.rb
class TransactionsController < ApplicationController
  # Add authentication/authorization as needed (e.g., using Devise, Pundit)
  # before_action :authenticate_user!
  before_action :set_transaction, only: [:update]
  before_action :load_categories, only: [:update] # Load categories for re-rendering the partial

  # PATCH /transactions/:id
  # PATCH /transactions/:id.turbo_stream
  def update
    if @transaction.update(transaction_params)
      render turbo_stream: turbo_stream.replace(@transaction, partial: "transactions/transaction_as_row", locals: { transaction: @transaction, categories: @categories })
    else
      render turbo_stream: turbo_stream.replace(@transaction, partial: "transactions/transaction_as_row", locals: { transaction: @transaction, categories: @categories }), status: :unprocessable_entity
    end
  end

  private

  def set_transaction
    # Ensure the transaction belongs to the current user or account context if necessary
    @transaction = Transaction.find(params[:id])
  end

  # Added method to load categories needed for rendering the partial
  def load_categories
    @categories = Category.order(:name).all
  end

  def transaction_params
    # Permit only the category_id (and others if added to the form)
    params.require(:transaction).permit(:category_id) # Add other editable fields here
  end
end
