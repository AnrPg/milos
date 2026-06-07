defmodule MilosTrainingWeb.FallbackController do
  use MilosTrainingWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid credentials"})
  end

  def call(conn, {:error, :invalid_refresh_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid refresh token"})
  end

  def call(conn, {:error, :token_issuance_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Authentication service unavailable"})
  end

  def call(conn, {:error, :registration_cleanup_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Registration could not be completed"})
  end

  def call(conn, {:error, :auth_dependency_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Authentication dependency unavailable"})
  end

  def call(conn, {:error, :rate_limiter_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Rate limiter unavailable"})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Not found"})
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Bad request"})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Unexpected server error"})
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
