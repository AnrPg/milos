defmodule MilosTraining.Infrastructure.Security.MemoryRateLimiter.TableOwner do
  @moduledoc """
  Owns the rate-limit ETS table for the lifetime of the application.

  ETS tables are destroyed when their owning process exits. Before this
  existed, whichever process happened to call `check_rate/4` first created
  (and so owned) the table - in production that's a transient per-request
  process; in tests, a transient `Task`. Either way, the table could vanish
  the moment its accidental owner terminated, crashing every other
  concurrent caller with "table identifier does not refer to an existing
  ETS table". A GenServer supervised for the application's lifetime doesn't
  have that problem: it never exits except on shutdown.

  This process does nothing after `init/1` - `MemoryRateLimiter` still
  talks to the `:public` table directly (no GenServer.call indirection) so
  concurrent rate checks stay lock-free.
  """

  use GenServer

  @table :milos_training_rate_limits

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    end

    {:ok, :owner}
  end
end
