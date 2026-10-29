# ADR-157, ADR-243: tests that need external tools run where they are installed.
missing_tools =
  [
    imagemagick: System.find_executable("magick") || System.find_executable("convert"),
    ffmpeg: System.find_executable("ffmpeg") && System.find_executable("ffprobe"),
    # ADR-243: myDATA XML is validated against AADE's XSDs.
    xmllint: System.find_executable("xmllint")
  ]
  |> Enum.filter(fn {_tag, path} -> is_nil(path) end)
  |> Enum.map(&elem(&1, 0))

ExUnit.start(exclude: missing_tools)
# TD-046: the RLS-enforcing role that ConnCase requests and `:rls_enforced` tests run as.
Palee.RLSCase.ensure_runtime_role!()
Ecto.Adapters.SQL.Sandbox.mode(Palee.Repo, :manual)
Palee.TestSupport.MemoryObjectStore.start()

if Palee.UnscopedQueryDetector.enabled?(), do: Palee.UnscopedQueryDetector.start()
