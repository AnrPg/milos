defmodule Palee.Application.AuthorizeProgramming do
  @moduledoc """
  A WOD is programmed for a person only when their package includes online
  programming, personal training, or both (ADR-225; ADR-125 for members).

  The role never implies it: members and athletes alike need the grant in
  their effective Finance contract (`ProgrammingGrant`). The check runs
  before any library copy or assignment write, independent of the tenant's
  ADR-040 rollout mode. Seasons are not checked here: buying a season is
  buying its programme (ADR-167).
  """

  alias Palee.{Finance, Identity}
  alias Palee.Finance.Domain.ProgrammingGrant

  @doc "`:ok` when every person may be programmed, else the first refusal."
  def call(context, user_ids) do
    with {:ok, _grants} <- grants(context, user_ids), do: :ok
  end

  @doc """
  `{:ok, %{user_id => :online_programming | :personal_training}}`, or
  `{:error, :programming_not_in_package, %{user_id, nickname, reason}}` for
  the first person whose package has neither.
  """
  def grants(_context, []), do: {:ok, %{}}

  def grants(%{organization_id: organization_id} = context, user_ids)
      when is_binary(organization_id) and is_list(user_ids) do
    Enum.reduce_while(user_ids, {:ok, %{}}, fn user_id, {:ok, grants} ->
      case context |> Finance.get_effective_entitlement(user_id) |> ProgrammingGrant.of() do
        {:ok, grant} -> {:cont, {:ok, Map.put(grants, user_id, grant)}}
        {:error, reason} -> {:halt, denial(user_id, reason)}
      end
    end)
  end

  def grants(_context, _user_ids), do: {:error, :organization_context_required}

  @doc """
  One person's grant, for screens that explain up front why programming is
  unavailable: `{:ok, grant}` or `{:error, reason}` (e.g.
  `:finance_channel_not_included`).
  """
  def grant_for(%{organization_id: organization_id} = context, user_id)
      when is_binary(organization_id) do
    context |> Finance.get_effective_entitlement(user_id) |> ProgrammingGrant.of()
  end

  defp denial(user_id, reason) do
    nickname =
      case Identity.find_by_id(user_id) do
        %{nickname: nickname} when is_binary(nickname) -> nickname
        _ -> nil
      end

    {:error, :programming_not_in_package,
     %{user_id: user_id, nickname: nickname, reason: to_string(reason)}}
  end
end
