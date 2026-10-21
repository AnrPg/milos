defmodule Palee.Finance.Queries.GetPackageCatalog do
  alias Palee.Finance.Domain.{PackageCatalogDocument, PackageType}
  alias Palee.Finance.FinanceStore

  def call do
    modules = Map.get(FinanceStore.get_finance_settings(), :package_modules)
    PackageCatalogDocument.build(modules || PackageType.default_modules())
  end
end
