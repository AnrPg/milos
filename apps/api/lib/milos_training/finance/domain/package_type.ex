defmodule MilosTraining.Finance.Domain.PackageType do
  @moduledoc """
  How a package is sold (ADR-096). The type is the key for presets and
  type-enforced fields; it never grants access by itself.
  """

  @types [
    %{key: "membership", phase: :a, billing_model: "recurring", module: "group_classes"},
    %{key: "class_pack", phase: :a, billing_model: "one_off", module: "group_classes"},
    %{key: "drop_in", phase: :a, billing_model: "one_off", module: "group_classes"},
    %{key: "trial", phase: :a, billing_model: "one_off", module: nil},
    %{key: "pt_pack", phase: :c, billing_model: "one_off", module: "personal_training"},
    %{key: "add_on", phase: :c, billing_model: "with_base", module: nil},
    %{key: "shared", phase: :c, billing_model: "recurring", module: nil},
    %{key: "corporate", phase: :c, billing_model: "recurring", module: "corporate_clients"}
  ]

  @recurring_billing_periods ["monthly", "quarterly", "semiannual", "annual", "custom"]
  @types_by_key Map.new(@types, &{&1.key, &1})

  @modules [
    %{key: "group_classes", phase: :a},
    %{key: "online_coaching", phase: :a},
    %{key: "open_gym", phase: :b},
    %{key: "events", phase: :b},
    %{key: "personal_training", phase: :c},
    %{key: "digital_content", phase: :c},
    %{key: "corporate_clients", phase: :c}
  ]

  def types, do: @types
  def keys, do: Enum.map(@types, & &1.key)
  def modules, do: @modules
  def module_keys, do: Enum.map(@modules, & &1.key)
  def default_modules, do: ["group_classes", "online_coaching"]

  def fetch(key) when is_binary(key) do
    case Map.fetch(@types_by_key, key) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, :invalid_package_type}
    end
  end

  def fetch(_), do: {:error, :invalid_package_type}

  def available?(%{phase: phase}),
    do: phase in MilosTraining.Finance.Domain.PackageCatalog.implemented_phases()

  def module_available?(key) do
    case Enum.find(@modules, &(&1.key == key)) do
      nil -> false
      module -> available?(module)
    end
  end

  def one_off?(%{billing_model: "one_off"}), do: true
  def one_off?(_), do: false

  def renewable?(%{billing_model: "recurring"}), do: true
  def renewable?(_), do: false

  @doc "Billing periods a type may use; one-off types always use `one_off`."
  def billing_periods(%{billing_model: "recurring"}), do: @recurring_billing_periods
  def billing_periods(%{billing_model: "one_off"}), do: ["one_off"]
  def billing_periods(%{billing_model: "with_base"}), do: ["with_base"]

  def default_billing_period(%{billing_model: "recurring"}), do: "monthly"
  def default_billing_period(%{billing_model: "one_off"}), do: "one_off"
  def default_billing_period(%{billing_model: "with_base"}), do: "with_base"

  def all_billing_periods, do: @recurring_billing_periods ++ ["one_off", "with_base"]
end
