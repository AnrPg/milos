defmodule Palee.Fiscal.Registry do
  @moduledoc """
  «Συμπλήρωση από το ΑΦΜ» (ADR-265): a Greek business's registry details
  by its ΑΦΜ, from AADE's RgWsPublic2 service through the
  `Fiscal.Ports.BusinessRegistry` of the organization's registry
  connection.

  The connection is the business's own (AADE issues the special
  credentials to each business for this service): one row of
  `fiscal_authority_connections` with authority `gr_registry`, environment
  `sandbox` or `production`, the AADE username in `user_id` and the
  password encrypted in `subscription_key` (like the myDATA key, ADR-243).
  It is never returned, logged or journaled.

  The ΑΦΜ's check digit is verified before any call, so a typo never
  spends the business's monthly quota.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{Connections, FiscalStore, TransmissionStore}
  alias Palee.Fiscal.Domain.TaxId

  @authority "gr_registry"
  @environments ~w(sandbox production)

  def environments, do: @environments

  defp adapter(environment) do
    :palee
    |> Application.fetch_env!(:fiscal_business_registries)
    |> Map.fetch!(environment)
  end

  @doc "The registry connection as staff see it (never the password), or nil."
  def connection(context) do
    context
    |> TransmissionStore.get_connection(@authority)
    |> public_connection()
  end

  defp public_connection(nil), do: nil

  defp public_connection(connection) do
    connection
    |> Map.take([:environment, :status, :updated_at])
    # ADR-273: the same name the save takes (`username`).
    |> Map.put(:username, connection.user_id)
    |> Map.merge(Connections.public_check(connection))
    |> Map.put(:has_password, is_binary(connection.subscription_key))
  end

  @doc false
  # ADR-273: «Δοκιμή σύνδεσης» looks up the business's own ΑΦΜ (one call
  # of the business's AADE quota) and answers with the name AADE has.
  def check_connection(context, connection, %Date{} = as_on) do
    identity = FiscalStore.get_identity(context)

    with {:ok, afm} <- own_afm(identity),
         {:ok, business} <- adapter(connection.environment).lookup(connection, afm, as_on) do
      {:ok, %{tax_id: afm, legal_name: business.legal_name}}
    end
  end

  defp own_afm(%{country_code: "GR", tax_id: tax_id}) when is_binary(tax_id) do
    case valid_afm(tax_id) do
      {:ok, afm} -> {:ok, afm}
      {:error, _reason} -> {:error, :tax_id_missing}
    end
  end

  defp own_afm(_identity), do: {:error, :tax_id_missing}

  @doc """
  Saves the registry connection: `environment` (`sandbox` or
  `production`), `username` and `password` (production; a saved password
  is kept when none is sent). Journals the change without the password.
  `{:ok, connection}` or `{:error, {:invalid_fields, errors}}`.
  """
  def save_connection(context, params, actor_id, %DateTime{} = now) do
    before = TransmissionStore.get_connection(context, @authority)

    with {:ok, attrs} <- validate(before, params) do
      FiscalStore.transaction(context, fn ->
        with {:ok, saved} <-
               TransmissionStore.save_connection(
                 context,
                 @authority,
                 attrs
                 |> Map.merge(Connections.saved_fields())
                 |> Map.merge(%{
                   updated_by_id: actor_id,
                   updated_by_platform: params[:updated_by_platform] == true
                 })
               ),
             {:ok, _entry} <-
               Fiscal.append(context, %{
                 event_type: "registry_connection_saved",
                 subject_type: "authority_connection",
                 subject_id: saved.id,
                 actor_id: actor_id,
                 occurred_at: now,
                 payload:
                   %{
                     authority: @authority,
                     environment: saved.environment,
                     user_id: saved.user_id,
                     password_changed: Map.has_key?(attrs, :subscription_key)
                   }
                   |> Connections.platform_mark(params)
               }) do
          {:ok, public_connection(saved)}
        end
      end)
    end
  end

  defp validate(before, params) do
    environment = params[:environment]
    user_id = clean(params[:username]) || (before && before.user_id)
    password = clean(params[:password])
    stored = before && before.subscription_key
    production? = environment == "production"

    errors =
      %{}
      |> add_error(environment not in @environments, :environment, "invalid")
      |> add_error(production? and is_nil(user_id), :username, "required")
      |> add_error(production? and is_nil(password) and is_nil(stored), :password, "required")
      |> add_error(is_binary(user_id) and String.length(user_id) > 100, :username, "too_long")
      |> add_error(is_binary(password) and String.length(password) > 200, :password, "too_long")

    if errors == %{} do
      attrs = %{environment: environment, user_id: user_id}
      {:ok, if(password, do: Map.put(attrs, :subscription_key, password), else: attrs)}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  @doc """
  The registry details of the business with ΑΦΜ `tax_id` on `as_on`:
  `{:ok, business}` (see `Fiscal.Ports.BusinessRegistry`) or
  `{:error, reason}`: `:invalid_tax_id` (check digit, checked first),
  `:registry_not_connected`, `:registry_credentials_rejected` (the
  connection is then marked invalid), `:registry_not_found`,
  `:registry_limit_reached`, `:registry_unavailable`.
  """
  def lookup(context, tax_id, %Date{} = as_on) do
    with {:ok, afm} <- valid_afm(tax_id),
         %{status: "active"} = connection <-
           TransmissionStore.get_connection(context, @authority) ||
             {:error, :registry_not_connected} do
      case adapter(connection.environment).lookup(connection, afm, as_on) do
        {:ok, business} ->
          {:ok, business}

        {:error, :credentials_rejected} ->
          Connections.mark_invalid(
            context,
            "registry",
            "credentials_rejected",
            "credentials_rejected",
            DateTime.utc_now()
          )

          {:error, :registry_credentials_rejected}

        {:error, :not_found} ->
          {:error, :registry_not_found}

        {:error, :limit_reached} ->
          {:error, :registry_limit_reached}

        {:error, _unavailable} ->
          {:error, :registry_unavailable}
      end
    else
      %{status: _invalid} -> {:error, :registry_credentials_rejected}
      {:error, _reason} = error -> error
    end
  end

  defp valid_afm(tax_id) do
    case TaxId.validate("GR", :tax_id, tax_id) do
      {:ok, afm} -> {:ok, afm}
      {:error, _reason} -> {:error, :invalid_tax_id}
    end
  end

  defp add_error(errors, true, field, code), do: Map.put(errors, field, [code])
  defp add_error(errors, false, _field, _code), do: errors

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(_value), do: nil
end
