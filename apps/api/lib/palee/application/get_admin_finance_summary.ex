defmodule Palee.Application.GetAdminFinanceSummary do
  alias Palee.Finance

  def call, do: {:ok, Finance.financial_summary()}
end
