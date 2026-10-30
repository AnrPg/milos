defmodule Palee.Application.CreateFinancePackage do
  alias Palee.Application.Fiscal.SoldItemTax
  alias Palee.Application.PackageBranches
  alias Palee.Application.Payments.OnlineSales
  alias Palee.Finance

  def call(params), do: Finance.create_package(params)

  @doc """
  ADR-186 §8: a branch manager's package is valid at their branches only.
  ADR-271: a paid package created while online payments work starts sold
  online, unless the request says otherwise (the owner's choice).
  """
  def call(context, params, now \\ DateTime.utc_now()) do
    with :ok <- SoldItemTax.check(context, params),
         {:ok, params} <- PackageBranches.for_create(context, params),
         {:ok, package} <-
           Finance.create_package(context, OnlineSales.owner_choice(params, now)) do
      package =
        if package[:sold_online_chosen_at],
          do: package,
          else: OnlineSales.default_on_create(context, package)

      {:ok, OnlineSales.with_visibility(context, package)}
    end
  end
end
