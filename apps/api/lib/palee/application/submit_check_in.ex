defmodule Palee.Application.SubmitCheckIn do
  @moduledoc """
  Records one Πώς νιώθω submission (ADR-140 §2). Like a PR (ADR-129), it may
  name the gym it was written in (`organization_slug`), which gives it gym
  provenance and the member's `check_in` default rung; without a gym it is
  personal and private. Runs in the owner's scope.
  """

  alias Palee.Application.BroadcastUserSync
  alias Palee.{Journal, Organizations, Wellbeing}

  def call(%{user_id: user_id, account: account} = context, params, now \\ DateTime.utc_now())
      when is_map(params) do
    with {:ok, organization_id} <- provenance(account, params),
         {:ok, check_in} <-
           Wellbeing.with_tenant_context(context, fn ->
             user_id
             |> attrs(organization_id, params, now)
             |> Wellbeing.submit_check_in()
           end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
        reason: "check_in_submitted",
        payload: %{check_in_id: check_in.id}
      )

      {:ok, check_in}
    end
  end

  defp attrs(user_id, organization_id, params, now) do
    %{
      user_id: user_id,
      organization_id: organization_id,
      recorded_at: now,
      recorded_tz: param(params, "recorded_tz") || "UTC",
      journal_visibility:
        Journal.initial_visibility(user_id, "check_in", is_binary(organization_id)),
      answers:
        params
        |> param("answers")
        |> List.wrap()
        |> Enum.map(&answer_attrs(&1, user_id))
    }
  end

  defp answer_attrs(answer, user_id) when is_map(answer) do
    %{
      "user_id" => user_id,
      "question_key" => param(answer, "question_key"),
      "value" => param(answer, "value"),
      "note" => param(answer, "note")
    }
  end

  defp answer_attrs(_answer, user_id), do: %{"user_id" => user_id}

  defp provenance(account, params) do
    case param(params, "organization_slug") do
      slug when is_binary(slug) and slug != "" ->
        case Organizations.resolve_tenant_context(account, slug) do
          {:ok, tenant_context} -> {:ok, tenant_context.organization_id}
          {:error, _reason} -> {:error, :check_in_organization_unavailable}
        end

      _personal ->
        {:ok, nil}
    end
  end

  @keys %{
    "organization_slug" => :organization_slug,
    "recorded_tz" => :recorded_tz,
    "answers" => :answers,
    "question_key" => :question_key,
    "value" => :value,
    "note" => :note
  }

  defp param(params, key), do: Map.get(params, key, Map.get(params, Map.fetch!(@keys, key)))
end
