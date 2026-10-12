ExUnit.start()
# TD-046: the RLS-enforcing role that ConnCase requests and `:rls_enforced` tests run as.
MilosTraining.RLSCase.ensure_runtime_role!()
Ecto.Adapters.SQL.Sandbox.mode(MilosTraining.Repo, :manual)
MilosTraining.TestSupport.MemoryObjectStore.start()
