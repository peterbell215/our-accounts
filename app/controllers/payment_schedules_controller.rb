# The frequencies a reader sets by hand for a category's regular payments.
#
# One action, because there is only one thing to do: rule on each payee in the category, all at once,
# from the table on the category's edit screen.  An upsert rather than the usual quartet — a ruling is a
# single choice against a payee, and most of them are "work it out", which is the absence of a record.
# The same shape, and for the same reasons, as ManualForecastsController.
class PaymentSchedulesController < ApplicationController
  # PATCH /categories/:category_id/payment_schedules
  def update
    @category = Category.find(params[:category_id])

    PaymentSchedule.apply(category: @category, rows: submitted_rows)
    redirect_to edit_category_path(@category), notice: "Payment frequencies saved."
  rescue ActiveRecord::RecordInvalid => e
    # Only reachable from a forged form: the select offers four frequencies, "work it out" and "not a
    # regular payment", and nothing else.  PaymentSchedule.apply rolls the whole screen back rather than
    # leaving half of it applied, so there is nothing to re-render around — say so and send them back.
    redirect_to edit_category_path(@category), status: :see_other,
                alert: "Those frequencies could not be saved: #{e.record.errors.full_messages.to_sentence}."
  end

  private
    # The doubled brackets are what make this strict about arrays: `expect` refuses a hash arriving where
    # an array of rows is expected, which is the whole reason it exists.  A row names its payee the way
    # Forecast::RegularPayments groups it — a counterparty, or a description where there is none.
    def submitted_rows
      params.expect(payment_schedules: [ [ :counterparty_id, :description, :cadence_months ] ])
    end
end
