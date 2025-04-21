class TransactionPresenter
  attr_reader :form, :transaction, :view

  def initialize(form, transaction, view)
    @form = form
    @transaction = transaction
    @view = view
    @categories = Category.order(:name).all
  end

  def date
    if transaction.persisted?
      transaction.date.strftime("%d/%m/%Y")
    else
      form.date_field :date, value: (transaction.date || Date.current).strftime("%Y-%m-%d"), class: "pure-input-1"
    end
  end

  def category
    form.select :category_id,
                view.options_from_collection_for_select(@categories, :id, :name, transaction.category_id),
                { include_blank: true },
                { class: "pure-input-1-2" }
  end

  def description
    if transaction.persisted?
      transaction.description
    else
      form.text_field :description, value: transaction.description, class: "pure-input-1"
    end
  end

  def amount
    if transaction.persisted?
      view.humanized_money transaction.amount, class: (transaction.balance_pence.positive? ? 'positive' : 'negative')
    else
      form.number_field :amount, step: '0.01', value: humanized_money(transaction.amount, symbol: false), class: "pure-input-1-2"
    end
  end
end
