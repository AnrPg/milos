defmodule MilosTraining.Finance.Queries.GetPackageCatalog do
  alias MilosTraining.Finance.Domain.{PackageCatalogDocument, PackageType}
  alias MilosTraining.Finance.FinanceStore

  def call do
    modules = Map.get(FinanceStore.get_finance_settings(), :package_modules)
    PackageCatalogDocument.build(modules || PackageType.default_modules())
  end
end
