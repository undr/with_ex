defmodule WithEx.Executor.State do
  @moduledoc false

  alias WithEx.Chain

  defstruct effects: %{}, tasks: [], result: nil

  @type error_type :: :error | :exit | :raise | :throw
  @type t :: %__MODULE__{
    effects: map(),
    tasks: list(),
    result: nil | {:ok, any()} | {:error, any()}
  }

  @error_types [:error, :exit, :raise, :throw]

  @spec assign(t(), :effect, {Chain.name(), any()}) :: t()
  def assign(%__MODULE__{effects: effects} = state, :effect, {name, value}) do
    %__MODULE__{state | effects: Map.put(effects, name, value)}
  end

  @spec assign(t(), :result, {Chain.name(), any()}) :: t()
  def assign(%__MODULE__{effects: effects} = state, :result, {name, value}) do
    %__MODULE__{state | effects: Map.put(effects, name, value), result: {:ok, value}}
  end

  @spec assign(t(), error_type(), {Chain.name(), any()}) :: t()
  def assign(%__MODULE__{} = state, error_type, reason) when error_type in @error_types do
    %__MODULE__{state | result: {error_type, reason}}
  end

  @spec assign(t(), :task, {Chain.name(), {Task.t(), Keyword.t()}}) :: t()
  def assign(%__MODULE__{tasks: tasks} = state, :task, task_data) do
    %__MODULE__{state | tasks: [task_data | tasks]}
  end
end
