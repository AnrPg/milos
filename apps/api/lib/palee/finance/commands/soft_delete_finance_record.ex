defmodule Palee.Finance.Commands.SoftDeleteFinanceRecord do
  alias Palee.Finance.FinanceStore

  def call(record_type, record_id, admin_id, params) do
    FinanceStore.soft_delete_finance_record(record_type, record_id, admin_id, params)
  end
end
