# app/controllers/transactions_controller.rb
class TransactionsController < ApplicationController
  before_action :set_account
  before_action :set_transaction, only: [:update, :destroy] # Add :destroy here
  before_action :load_categories, only: [:new, :create, :update] # Ensure categories are loaded

  # ... (index action remains the same) ...

  # GET /accounts/:account_id/transactions/new
  def new
    # Find the latest transaction date for this account
    latest_date = @account.transactions.maximum(:date)

    @transaction = @account.transactions.new(date: latest_date) # Build a new transaction for the account

    # Render the turbo stream view to prepend the new row before the marker
    render turbo_stream: turbo_stream.before("end-of-table-marker",
                                             partial: "transactions/transaction_as_row",
                                             locals: { transaction: @transaction, account: @account, categories: @categories })
  end

  # POST /accounts/:account_id/transactions
  def create
    @transaction = @account.transactions.build(transaction_params)
    if @transaction.save
      # Replace the temporary row (identified by dom_id(@transaction, 'new'))
      # with the persisted row after successful creation.
      render turbo_stream: turbo_stream.replace(helpers.dom_id(@transaction, "new"),
                                                partial: "transactions/transaction_as_row",
                                                locals: { transaction: @transaction, account: @account, categories: @categories })
    else
      # If saving fails, re-render the row with errors (within the temporary row).
      # Ensure the temporary ID is used so Turbo knows which element to update.
      render turbo_stream: turbo_stream.replace(helpers.dom_id(@transaction, "new"),
                                                partial: "transactions/transaction_as_row",
                                                locals: { transaction: @transaction, account: @account, categories: @categories }),
             status: :unprocessable_entity
    end
  end

  # PATCH /accounts/:account_id/transactions/:id
  def update
    if @transaction.update(transaction_params)
      render turbo_stream: turbo_stream.replace(@transaction,
                                                partial: "transactions/transaction_as_row",
                                                locals: { transaction: @transaction, account: @account, categories: @categories })
    else
      render turbo_stream: turbo_stream.replace(@transaction,
                                                partial: "transactions/transaction_as_row",
                                                locals: { transaction: @transaction, account: @account, categories: @categories }),
                                                status: :unprocessable_entity
    end
  end

  # DELETE /accounts/:account_id/transactions/:id
  def destroy
    @transaction.destroy
    # Respond with Turbo Stream to remove the element from the page
    render turbo_stream: turbo_stream.remove(@transaction)
  end

  # ... (destroy action if it exists) ...

  private

  def set_transaction
    # Ensure the transaction belongs to the current account
    @transaction = @account.transactions.find(params[:id])
  end

  def set_account
    @account = Account.find(params[:account_id])
  end

  def load_categories
    @categories = Category.order(:name).all
  end

  def transaction_params
    # Permit all the fields submitted by the single form
    params.require(:transaction).permit(:category_id, :date, :description, :amount)
  end
end
