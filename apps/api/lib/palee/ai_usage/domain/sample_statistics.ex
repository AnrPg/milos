defmodule Palee.AiUsage.Domain.SampleStatistics do
  @moduledoc """
  Descriptive statistics of repeated measurements (ADR-152): mean, sample
  standard deviation (n − 1) and the standard error of the mean (sd / √n).
  With a single measurement the spread is unknown (`nil`), never zero.
  """

  def describe([]), do: %{n: 0, mean: nil, sd: nil, se: nil, min: nil, max: nil}

  def describe(values) when is_list(values) do
    n = length(values)
    mean = Enum.sum(values) / n

    sd =
      if n > 1,
        do: :math.sqrt(Enum.sum(Enum.map(values, &((&1 - mean) ** 2))) / (n - 1)),
        else: nil

    %{
      n: n,
      mean: mean,
      sd: sd,
      se: sd && sd / :math.sqrt(n),
      min: Enum.min(values),
      max: Enum.max(values)
    }
  end
end
