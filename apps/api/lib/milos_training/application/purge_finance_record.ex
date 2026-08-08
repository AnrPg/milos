defmodule MilosTraining.Application.PurgeFinanceRecord do
  alias MilosTraining.Application.{PasswordVerifier, RecordAnalyticsEvent}
  alias MilosTraining.{Finance, Identity}

  def call(admin_id, record_type, record_id, params) do
    params = string_key_map(params || %{})

    with {:ok, admin} <- fetch_admin(admin_id),
         :ok <- verify_password(params["password"], admin.password_hash),
         {:ok, result} <-
           Finance.soft_delete_finance_record(record_type, record_id, admin_id, params) do
      RecordAnalyticsEvent.call_unsafe("finance_record_soft_deleted", %{
        user_id: admin_id,
        context_type: "finance_soft_delete",
        context_id: record_id,
        metadata: %{
          record_type: record_type,
          deletion_reason: params["reason"] || params["deletion_reason"]
        }
      })

      {:ok, result}
    end
  end

  defp fetch_admin(admin_id) do
    case Identity.find_by_id(admin_id) do
      nil ->
        PasswordVerifier.no_user_verify()
        {:error, :not_found}

      admin ->
        {:ok, admin}
    end
  end

  defp verify_password(password, _hash) when not is_binary(password),
    do: {:error, :invalid_password}

  defp verify_password("", _hash), do: {:error, :invalid_password}

  defp verify_password(password, hash) do
    if PasswordVerifier.verify(password, hash) do
      :ok
    else
      {:error, :invalid_password}
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
