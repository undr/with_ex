defmodule WithEx.Executor do
  @moduledoc false

  alias WithEx.Executor.State
  alias WithEx.Chain

  @spec exec(Chain.t()) :: {:ok, any(), map()} | {:error, {Chain.name(), any()}}
  def exec(%Chain{operations: operations, final_hooks: final_hooks}) do
    operations
    |> Enum.reverse()
    |> apply_operations(%State{})
    |> handle_chain_result(final_hooks)
  end

  defp apply_operations([], state) do
    {_, state} = maybe_await_tasks(state)
    state
  end

  defp apply_operations([op | operations], state) do
    case apply_operation(op, state) do
      {:next, state} ->
        apply_operations(operations, state)

      {:halt, state} ->
        state
    end
  end

  defp apply_operation({_, {:inspect, opts}}, state) do
    {action, %{effects: effects} = state} = maybe_await_tasks(state)

    if opts[:only] do
      effects
      |> Map.take(List.wrap(opts[:only]))
      |> IO.inspect(opts)
    else
      IO.inspect(effects, opts)
    end

    {action, state}
  end

  defp apply_operation({name, {:run, fun}}, state) do
    with {:next, state} <- maybe_await_tasks(state) do
      case apply_fun(fun, [state.effects]) do
        :ok ->
          {:next, state}

        {:ok, value} ->
          {:next, State.assign(state, :result, {name, value})}

        {:exit, reason} ->
          {:halt, State.assign(state, :exit, {name, reason})}

        {:throw, reason} ->
          {:halt, State.assign(state, :throw, {name, reason})}

        {:raise, reason} ->
          {:halt, State.assign(state, :raise, {name, reason})}

        {:error, reason} ->
          {:halt, State.assign(state, :error, {name, reason})}

        other ->
          raise "expected WithEx.Chain callback named `#{Kernel.inspect(name)}` to return either :ok or {:ok, value} or {:error, value}, got: #{Kernel.inspect(other)}"
      end
    end
  end

  defp apply_operation({name, {:run_async, fun, opts}}, state) do
    supervisor = Keyword.get(opts, :supervisor, WithEx.TaskSupervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        apply_fun(fun, [state.effects])
      end)

    {:next, State.assign(state, :task, {name, {task, opts}})}
  end

  defp apply_operation({name, {:put, value}}, state) do
    with {:next, state} <- maybe_await_tasks(state) do
      {:next, State.assign(state, :result, {name, value})}
    end
  end

  defp maybe_await_tasks(%{tasks: []} = state) do
    {:next, state}
  end

  defp maybe_await_tasks(%{tasks: tasks} = state) do
    state = %State{state | tasks: []}

    tasks
    |> Enum.reverse()
    |> Enum.map(&await_for_task/1)
    |> Enum.reduce({:next, state}, &handle_task_result/2)
  end

  defp await_for_task({name, {task, yield_opts}}) do
    timeout = Keyword.get(yield_opts, :timeout, 5000)

    {name, Task.yield(task, timeout) || Task.shutdown(task)}
  end

  defp handle_task_result({name, result}, {action, state}) do
    case result do
      {:ok, :ok} ->
        {action(action, :next), state}

      {:ok, {:ok, value}} ->
        if action == :halt do
          {:halt, State.assign(state, :effect, {name, value})}
        else
          {:next, State.assign(state, :result, {name, value})}
        end

      {:ok, {:error, reason}} ->
        {action(action, :halt), State.assign(state, :error, {name, reason})}

      {:ok, {:exit, reason}} ->
        {action(action, :halt), State.assign(state, :exit, {name, reason})}

      {:ok, {:throw, reason}} ->
        {action(action, :halt), State.assign(state, :throw, {name, reason})}

      {:ok, {:raise, reason}} ->
        {action(action, :halt), State.assign(state, :raise, {name, reason})}

      {:exit, reason} ->
        {action(action, :halt), State.assign(state, :error, {name, {:exit, reason}})}

      nil ->
        {action(action, :halt), State.assign(state, :error, {name, :timeout})}

      other ->
        raise "expected WithEx.Chain callback named `#{Kernel.inspect(name)}` to return either :ok or {:ok, value} or {:error, value}, got: #{Kernel.inspect(other)}"
    end
  end

  defp handle_chain_result(%State{result: result, effects: effects}, final_hooks) do
    Enum.each(final_hooks, &(apply_fun(&1, [result, effects])))

    case result do
      {:ok, value} ->
        {:ok, value, effects}

      {:raise, {_, {exception, stacktrace}}} ->
        reraise(exception, stacktrace)

      {:exit, {_, reason}} ->
        exit(reason)

      {:throw, {_, reason}} ->
        throw(reason)

      {:error, reason} ->
        {:error, reason, effects}
    end
  end

  defp apply_fun(fun, args) when is_function(fun) do
    apply(fun, args)
  rescue
    exception -> {:raise, {exception, __STACKTRACE__}}
  catch
    :exit, reason -> {:exit, reason}
    :throw, error -> {:throw, error}
  end

  defp apply_fun({mod, fun, largs}, rargs) do
    apply(mod, fun, largs ++ rargs)
  rescue
    exception -> {:raise, {exception, __STACKTRACE__}}
  catch
    :exit, reason -> {:exit, reason}
    :throw, error -> {:throw, error}
  end

  defp action(:halt, _),
    do: :halt

  defp action(_, action),
    do: action
end
