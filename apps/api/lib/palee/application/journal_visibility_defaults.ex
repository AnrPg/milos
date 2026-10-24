defmodule Palee.Application.JournalVisibilityDefaults do
  @moduledoc """
  `GET/PUT /api/me/journal/visibility-defaults` (ADR-139 §3, ADR-196): the
  rung a new entry of each kind starts on, edited from Εγώ › Κοινοποίηση &
  ορατότητα («Προεπιλογή νέων καταχωρήσεων»). Setting a default changes new
  entries only. The `pr` default is the «Ο coach μου βλέπει › PRs» switch,
  which also moves existing PRs (`SetPRCoachVisibility`), so it is not set
  here.
  """

  alias Palee.Journal

  @settable ~w(workout note check_in)

  def call(%{user_id: user_id} = context) do
    {:ok, Journal.with_context(context, fn -> Journal.visibility_defaults(user_id) end)}
  end

  def put(%{user_id: user_id} = context, kind, rung) do
    if kind in @settable do
      Journal.with_context(context, fn ->
        with :ok <- Journal.put_visibility_default(user_id, kind, rung),
             do: {:ok, Journal.visibility_defaults(user_id)}
      end)
    else
      {:error, :unknown_kind}
    end
  end
end
