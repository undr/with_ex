defmodule WithEx.Executor.State do
  @moduledoc false

  alias WithEx.Chain

  defstruct effects: %{}, tasks: [], result: nil

  @type t :: %__MODULE__{
    effects: map(),
    tasks: list(),
    result: nil | {:ok, any()} | {:error, any()}
  }

  @spec assign(t(), :effect, {Chain.name(), any()}) :: t()
  def assign(%__MODULE__{effects: effects} = state, :effect, {name, value}) do
    %__MODULE__{state | effects: Map.put(effects, name, value)}
  end

  @spec assign(t(), :result, {Chain.name(), any()}) :: t()
  def assign(%__MODULE__{effects: effects} = state, :result, {name, value}) do
    %__MODULE__{state | effects: Map.put(effects, name, value), result: {:ok, value}}
  end

  @spec assign(t(), :error, {Chain.name(), any()}) :: t()
  def assign(%__MODULE__{} = state, :error, reason) do
    %__MODULE__{state | result: {:error, reason}}
  end

  @spec assign(t(), :task, {Chain.name(), {Task.t(), Keyword.t()}}) :: t()
  def assign(%__MODULE__{tasks: tasks} = state, :task, task_data) do
    %__MODULE__{state | tasks: [task_data | tasks]}
  end
end
