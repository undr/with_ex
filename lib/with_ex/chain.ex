defmodule WithEx.Chain do
  @moduledoc ""

  defstruct operations: [], names: MapSet.new(), final_hooks: MapSet.new()

  @typep effects :: map()
  @typep result :: :ok | {:ok, any()} | {:error, any()}
  @typep run :: (effects() -> {:ok | :error, any()}) | {module(), atom(), [any()]}
  @typep final_hook :: (result(), effects() -> no_return()) | {module(), atom(), [any()]}
  @typep operation :: {:put, any()} |
                      {:run, run()} |
                      {:run_async, run(), Keyword.t()} |
                      {:inspect, Keyword.t()}
  @typep operations :: [{name(), operation()}]
  @typep names :: MapSet.t()
  @typep final_hooks :: MapSet.t()
  @type name :: any()
  @type t :: %__MODULE__{
    operations: operations(),
    names: names(),
    final_hooks: final_hooks()
  }

  @doc """
  Create new chain.

  ## Examples

      iex> WithEx.Chain.new()
      %WithEx.Chain{operations: [], names: MapSet.new()}

  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Appends the second chain to the first one.

  All names must be unique between both structures.

  ## Example

      iex> lhs = WithEx.Chain.new() |> WithEx.Chain.run(:left, fn state -> {:ok, state} end)
      iex> rhs = WithEx.Chain.new() |> WithEx.Chain.run(:right, fn state -> {:error, state} end)
      iex> WithEx.Chain.append(lhs, rhs) |> WithEx.Chain.to_list() |> Keyword.keys()
      [:left, :right]

  """
  @spec append(t(), t()) :: t()
  def append(lhs, rhs) do
    merge_structs(lhs, rhs, &(&2 ++ &1))
  end

  @doc """
  Prepends the second chain to the first one.

  All names must be unique between both structures.

  ## Example

      iex> lhs = WithEx.Chain.new() |> WithEx.Chain.run(:left, fn state -> {:ok, state} end)
      iex> rhs = WithEx.Chain.new() |> WithEx.Chain.run(:right, fn state -> {:error, state} end)
      iex> WithEx.Chain.prepend(lhs, rhs) |> WithEx.Chain.to_list() |> Keyword.keys()
      [:right, :left]

  """
  @spec prepend(t(), t()) :: t()
  def prepend(lhs, rhs) do
    merge_structs(lhs, rhs, &(&1 ++ &2))
  end

  @doc """
  Adds a function to run as part of the chain.

  The function should return either `{:ok, value}` or `{:error, value}`,
  and receives the state as an argument.

  ## Example

      WithEx.Chain.run(chain, :write, fn %{image: image} ->
        with :ok <- File.write(image.name, image.contents) do
          {:ok, nil}
        end
      end)
  """
  @spec run(t(), name(), run()) :: t()
  def run(%__MODULE__{} = chain, name, run) when is_function(run, 1) do
    add_operation(chain, name, {:run, run})
  end

  @doc """
  Adds a function to run as part of the chain.

  Similar to `run/3`, but allows to pass module name, function and arguments.
  The function should return either `{:ok, value}` or `{:error, value}`, and
  receives the state as the argument (prepended to those passed
  in the call to the function).
  """
  @spec run(t(), name(), module(), atom(), [any()]) :: t()
  def run(%__MODULE__{} = chain, name, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    add_operation(chain, name, {:run, {mod, fun, args}})
  end

  @doc """
  Adds a function to asynchronously run as part of the chain.

  The function should return either `{:ok, value}` or `{:error, value}`,
  and receives the state as an argument.

  ## Example

      WithEx.Chain.run(chain, :write, fn %{image: image} ->
        with :ok <- File.write(image.name, image.contents) do
          {:ok, nil}
        end
      end)
  """
  @spec run_async(t(), name(), run()) :: t()
  @spec run_async(t(), name(), run(), Keyword.t()) :: t()
  def run_async(%__MODULE__{} = chain, name, run, opts \\ []) when is_function(run, 1) do
    add_operation(chain, name, {:run_async, run, opts})
  end

  @doc """
  Adds a function to asynchronously run as part of the chain.

  Similar to `run_async/3`, but allows to pass module name, function and arguments.
  The function should return either `{:ok, value}` or `{:error, value}`, and
  receives the state as the first argument (prepended to those passed
  in the call to the function).
  """
  @spec run_async(t(), name(), module(), atom(), [any()]) :: t()
  @spec run_async(t(), name(), module(), atom(), [any()], Keyword.t()) :: t()
  def run_async(%__MODULE__{} = chain, name, mod, fun, args, opts \\ [])
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    add_operation(chain, name, {:run_async, {mod, fun, args}, opts})
  end

  @doc """
  Adds a value to the state under the given name.

  The given `value` is added to the chain. If you would like to run arbitrary
  functions as part of your chain, see `run/3` or `run/5`.

  ## Example

      WithEx.Chain.new()
      |> WithEx.Chain.put(:x, x)
      |> WithEx.Chain.put(:y, y)
      |> WithEx.Chain.run(:sum, fn %{x: x, y: y} -> {:ok, x + y} end)
      |> WithEx.exec()

  In the example above there isn't a large benefit in putting the
  `x` and `y in the chain, because you could also access the
  these variables directly inside the anonymous function.

  However, the benefit of `put/3` is when composing `WithEx.Chain`s.
  If the sum operations above were defined in another module,
  you could use `put(:x, x)` to inject state that will be accessed
  by other functions down the chain, removing the need to pass both
  `x` and `y` values around.
  """
  @spec put(t(), name(), any()) :: t()
  def put(chain, name, value) do
    add_operation(chain, name, {:put, value})
  end

  @doc """
  Inspects results from a chain

  By default, the name is shown as a label to the inspect, custom labels are
  supported through the `IO.inspect/2` `label` option.

  ## Options

  All options for IO.inspect/2 are supported, it also support the following ones:

    * `:only` - A field or a list of fields to inspect, will print the entire
      map by default.

  ## Examples

      WithEx.Chain.new()
      |> WithEx.Chain.put(:person_a, person_a)
      |> WithEx.Chain.put(:person_b, person_b)
      |> WithEx.Chain.inspect()
      |> WithEx.Chain.exec()

  Prints:
      %{person_a: %Person{...}, person_b: %Person{...}}

  We can use the `:only` option to limit which fields will be printed:

      WithEx.Chain.new()
      |> WithEx.Chain.put(:person_a, person_a)
      |> WithEx.Chain.put(:person_b, person_b)
      |> WithEx.Chain.inspect(only: :person_a)
      |> WithEx.Chain.exec()

  Prints:
      %{person_a: %Person{...}}

  """
  @spec inspect(t(), Keyword.t()) :: t()
  def inspect(chain, opts \\ []) do
    Map.update!(chain, :operations, &[{:inspect, {:inspect, opts}} | &1])
  end

  @doc """
  Returns the list of operations stored in `chain`.

  Always use this function when you need to access the operations you
  have defined in `WithEx.Chain`. Inspecting the `WithEx.Chain` struct internals
  directly is discouraged.
  """
  @spec to_list(t()) :: [{name(), any()}]
  def to_list(%__MODULE__{operations: operations}) do
    Enum.reverse(operations)
  end

  @doc """
  Appends the Chain with a function that will be triggered after chain execution.

  Registering duplicated final hook is not allowed and would raise an exception.
  """
  @spec finally(t(), final_hook()) :: t()
  def finally(%__MODULE__{final_hooks: final_hooks} = chain, hook) do
    if MapSet.member?(final_hooks, hook) do
      raise ArgumentError, """
        #{format_callback(hook)} is already defined as final hook for WithEx.Chain:

        #{Kernel.inspect(chain)}
      """
    end

    %{chain | final_hooks: MapSet.put(final_hooks, hook)}
  end

  def exec(chain) do
    WithEx.Executor.exec(chain)
  end

  defp merge_structs(%__MODULE__{} = lhs, %__MODULE__{} = rhs, joiner) do
    %{names: lhs_names, operations: lhs_ops} = lhs
    %{names: rhs_names, operations: rhs_ops} = rhs

    case MapSet.intersection(lhs_names, rhs_names) |> MapSet.to_list() do
      [] ->
        %__MODULE__{
          names: MapSet.union(lhs_names, rhs_names),
          operations: joiner.(lhs_ops, rhs_ops)
        }

      common ->
        raise ArgumentError, """
        error when merging the following WithEx.Pipeline structs:

        #{Kernel.inspect(lhs)}

        #{Kernel.inspect(rhs)}

        both declared operations: #{Kernel.inspect(common)}
        """
    end
  end

  defp add_operation(%__MODULE__{} = chain, name, operation) do
    %{operations: operations, names: names} = chain

    if MapSet.member?(names, name) do
      raise "#{Kernel.inspect(name)} is already a member of the WithEx.Chain: \n#{Kernel.inspect(chain)}"
    else
      %{
        chain |
        operations: [{name, operation} | operations],
        names: MapSet.put(names, name)
      }
    end
  end

  defp format_callback({m, f, a}),
    do: "#{Kernel.inspect(m)}.#{f}/#{length(a) + 2}"

  defp format_callback(cb),
    do: Kernel.inspect(cb)
end
