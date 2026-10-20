defmodule MilosTraining.Trials.Ports.TrialStore do
  @moduledoc """
  Persistence port for trial policies and trial requests (ADR-144). Every
  call runs in the caller's `RepoContext`: the box's scope for its policy and
  queue, the person's for their own trials.
  """

  alias MilosTraining.Trials.{TrialPolicy, TrialRequest}

  @type context :: map()
  @type id :: binary()
  @type window :: %{from: DateTime.t(), to: DateTime.t()}

  @callback get_policy(context()) :: TrialPolicy.t() | nil
  @callback put_policy(context(), map()) :: {:ok, TrialPolicy.t()} | {:error, Ecto.Changeset.t()}

  @callback insert_request(context(), map()) ::
              {:ok, TrialRequest.t()} | {:error, Ecto.Changeset.t()}
  @callback get_request(context(), id()) :: TrialRequest.t() | nil
  @callback get_request_by_booking(context(), id()) :: TrialRequest.t() | nil
  @callback get_request_by_operation(context(), id(), Ecto.UUID.t()) :: TrialRequest.t() | nil
  @callback update_request(context(), TrialRequest.t(), map()) ::
              {:ok, TrialRequest.t()} | {:error, Ecto.Changeset.t()}

  @doc "The box's trials, filtered by `statuses`, a person and an optional window."
  @callback list_requests(context(), %{
              optional(:statuses) => [String.t()],
              optional(:user_id) => id(),
              optional(:scheduled_class_id) => id(),
              optional(:from) => DateTime.t(),
              optional(:to) => DateTime.t(),
              optional(:limit) => pos_integer()
            }) :: [TrialRequest.t()]

  @doc "A person's own trials at every box (the person's scope)."
  @callback list_person_requests(context(), id(), %{optional(:since) => DateTime.t()}) ::
              [TrialRequest.t()]

  @doc "The statuses of every trial a person has had at the box in scope."
  @callback person_statuses(context(), id()) :: [String.t()]

  @doc "Trials in classes starting inside the window that use up a weekly place."
  @callback count_in_window(context(), window(), [String.t()]) :: non_neg_integer()

  @doc "Open trials per class (they hold the class's trial seats)."
  @callback open_per_class(context(), [id()]) :: %{id() => non_neg_integer()}

  @doc "Counts per status for trials whose class started since `since`."
  @callback stats(context(), DateTime.t()) :: %{String.t() => non_neg_integer()}

  @doc "Trial requests that came from club events' trial offers, per event and status (ADR-153)."
  @callback referral_event_stats(context(), [id()]) :: %{
              id() => %{String.t() => non_neg_integer()}
            }

  @doc "Runs `fun` in one transaction holding the box's trial lock (limits stay exact)."
  @callback with_box_lock(context(), (-> result)) :: result when result: term()
end
