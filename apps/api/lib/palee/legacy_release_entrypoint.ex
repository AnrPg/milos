defmodule MilosTraining.Release do
  @moduledoc """
  Compatibility entry point for the deployed manifests, which still run
  `bin/milos_training eval "MilosTraining.Release.migrate()"` (TD-109).
  Remove it, with the `bin/milos_training` link in the Dockerfile, once the
  infrastructure rename to Palee lands.
  """

  defdelegate migrate(), to: Palee.Release
  defdelegate purge_tenant_data_except_saas_owner(), to: Palee.Release
end
