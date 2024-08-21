defmodule WithEx.ChainTest do
  use ExUnit.Case
  doctest WithEx.Chain

  alias WithEx.Chain

  def run_ok(effects),
    do: {:ok, effects}

  def sum_ok(x, y, %{}),
    do: {:ok, x + y}

  def sum_error(_x, _y, %{}),
    do: {:error, :sum_reason}

  def prod_ok(x, y, %{}),
    do: {:ok, x * y}

  def prod_error(_x, _y, %{}),
    do: {:error, :prod_reason}

  def pow2_ok(%{sum: value}),
    do: {:ok, :math.pow(value, 2) |> round()}

  def pow2_error(%{sum: _sum}),
    do: {:error, :pow2_reason}

  test "new" do
    assert Chain.new() == %Chain{}
  end

  test "inspect" do
    chain = Chain.new() |> Chain.inspect()

    assert chain.names == MapSet.new([])
    assert chain.operations == [{:inspect, {:inspect, []}}]
  end

  describe "&run/3 and &run_async/3" do
    test "with fun" do
      fun = fn effects -> {:ok, effects} end
      chain = Chain.new() |> Chain.run(:fun, fun)

      assert chain.names == MapSet.new([:fun])
      assert chain.operations == [{:fun, {:run, fun}}]

      chain = Chain.new() |> Chain.run_async(:fun, fun)

      assert chain.names == MapSet.new([:fun])
      assert chain.operations == [{:fun, {:run_async, fun, []}}]
    end

    test "named with tuple" do
      fun = fn effects -> {:ok, effects} end
      chain = Chain.new() |> Chain.run({:fun, 3}, fun)

      assert chain.names == MapSet.new([{:fun, 3}])
      assert chain.operations == [{{:fun, 3}, {:run, fun}}]

      chain = Chain.new() |> Chain.run_async({:fun, 3}, fun)

      assert chain.names == MapSet.new([{:fun, 3}])
      assert chain.operations == [{{:fun, 3}, {:run_async, fun, []}}]
    end

    test "named with char_list" do
      fun = fn effects -> {:ok, effects} end
      chain = Chain.new() |> Chain.run('myFunction', fun)

      assert chain.names == MapSet.new(['myFunction'])
      assert chain.operations == [{'myFunction', {:run, fun}}]

      chain = Chain.new() |> Chain.run_async('myFunction', fun)

      assert chain.names == MapSet.new(['myFunction'])
      assert chain.operations == [{'myFunction', {:run_async, fun, []}}]
    end

    test "with mfa" do
      chain = Chain.new() |> Chain.run(:fun, {__MODULE__, :run_ok, []})

      assert chain.names == MapSet.new([:fun])
      assert chain.operations == [{:fun, {:run, {__MODULE__, :run_ok, []}}}]

      chain = Chain.new() |> Chain.run_async(:fun, {__MODULE__, :run_ok, []})

      assert chain.names == MapSet.new([:fun])
      assert chain.operations == [{:fun, {:run_async, {__MODULE__, :run_ok, []}, []}}]
    end

    test "with invalid arity" do
      fun = fn -> nil end

      assert_raise FunctionClauseError, fn ->
        Chain.new() |> Chain.run(:fun, fun)
      end

      assert_raise FunctionClauseError, fn ->
        Chain.new() |> Chain.run_async(:fun, fun)
      end
    end
  end

  describe "&append/2 and &prepend/2" do
    test "without repetition" do
      fun = fn _ -> :ok end
      lhs = Chain.new() |> Chain.run(:one, fun) |> Chain.run(:two, fun)
      rhs = Chain.new() |> Chain.run(:three, fun) |> Chain.run(:four, fun)

      merged = Chain.append(lhs, rhs)
      operations = Keyword.keys(merged.operations)
      assert merged.names == MapSet.new([:one, :two, :three, :four])
      assert operations   == [:four, :three, :two, :one]

      merged = Chain.prepend(lhs, rhs)
      operations = Keyword.keys(merged.operations)
      assert merged.names == MapSet.new([:one, :two, :three, :four])
      assert operations   == [:two, :one, :four, :three]
    end

    test "with repetition" do
      fun = fn _ -> :ok end
      chain = Chain.new() |> Chain.run(:run, fun)

      assert_raise ArgumentError, ~r"both declared operations: \[:run\]", fn ->
        Chain.append(chain, chain)
      end

      assert_raise ArgumentError, ~r"both declared operations: \[:run\]", fn ->
        Chain.prepend(chain, chain)
      end
    end
  end


  test "&to_list/0" do
    chain =
      Chain.new()
      |> Chain.put(:put, "value")
      |> Chain.run(:run, fn changes -> {:ok, changes} end)
      |> Chain.run_async(:run_async, fn changes -> {:ok, changes} end)
      |> Chain.inspect(only: :run, label: "test")

    assert [
      {:put, {:put, "value"}},
      {:run, {:run, _}},
      {:run_async, {:run_async, _, []}},
      {:inspect, {:inspect, [only: :run, label: "test"]}}
    ] = Chain.to_list(chain)
  end

  test "&put/3" do
    name = :halo
    value = "statue"

    chain = Chain.new() |> Chain.put(name, value)

    assert chain.names == MapSet.new([name])
    assert chain.operations == [{name, {:put, value}}]
  end

  test "repeating an operation" do
    fun = fn _ -> :ok end

    assert_raise RuntimeError, ~r":run is already a member", fn ->
      Chain.new() |> Chain.run(:run, fun) |> Chain.run(:run, fun)
    end
  end

  describe "&exec/1" do
    test "with inspect" do
      import ExUnit.CaptureIO

      chain =
        Chain.new()
        |> Chain.inspect()
        |> Chain.put(:put1, 1)
        |> Chain.put(:put2, 2)
        |> Chain.inspect(only: [:put1])
        |> Chain.inspect(only: :put2)

      assert capture_io(fn ->
        assert {:ok, 2, %{put1: 1, put2: 2}} = Chain.exec(chain)
      end) == "%{}\n%{put1: 1}\n%{put2: 2}\n"
    end

    test "success with functions" do
      chain =
        Chain.new()
        |> Chain.put(:x, 5)
        |> Chain.put(:y, 10)
        |> Chain.run(:sum, &({:ok, &1.x + &1.y}))
        |> Chain.run(:pow2, &({:ok, :math.pow(&1.sum, 2) |> round()}))

      assert {:ok, 225, %{x: 5, y: 10, sum: 15, pow2: 225}} == Chain.exec(chain)
    end

    test "success with mfa" do
      chain =
        Chain.new()
        |> Chain.run(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run(:pow2, {__MODULE__, :pow2_ok, []})

      assert {:ok, 225, %{sum: 15, pow2: 225}} == Chain.exec(chain)
    end

    test "error with functions" do
      chain =
        Chain.new()
        |> Chain.put(:x, 5)
        |> Chain.put(:y, 10)
        |> Chain.run(:sum, fn _ -> {:error, :sum_reason} end)
        |> Chain.run(:pow2, &({:ok, :math.pow(&1.sum, 2) |> round()}))

      assert {:error, {:sum, :sum_reason}, %{x: 5, y: 10}} == Chain.exec(chain)

      chain =
        Chain.new()
        |> Chain.put(:x, 5)
        |> Chain.put(:y, 10)
        |> Chain.run(:sum, &({:ok, &1.x + &1.y}))
        |> Chain.run(:pow2, fn _ -> {:error, :pow2_reason} end)

      assert {:error, {:pow2, :pow2_reason}, %{x: 5, y: 10, sum: 15}} == Chain.exec(chain)
    end

    test "error with mfa" do
      chain =
        Chain.new()
        |> Chain.run(:sum, {__MODULE__, :sum_error, [5, 10]})
        |> Chain.run(:pow2, {__MODULE__, :pow2_ok, []})

      assert {:error, {:sum, :sum_reason}, %{}} == Chain.exec(chain)

      chain =
        Chain.new()
        |> Chain.run(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run(:pow2, {__MODULE__, :pow2_error, []})

      assert {:error, {:pow2, :pow2_reason}, %{sum: 15}} == Chain.exec(chain)
    end

    test "async success with functions" do
      chain =
        Chain.new()
        |> Chain.put(:x, 5)
        |> Chain.put(:y, 10)
        |> Chain.run_async(:sum, &({:ok, &1.x + &1.y}))
        |> Chain.run_async(:prod, &({:ok, &1.x * &1.y}))

      assert {:ok, 50, %{x: 5, y: 10, sum: 15, prod: 50}} == Chain.exec(chain)
    end

    test "async success with mfa" do
      chain =
        Chain.new()
        |> Chain.run_async(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run_async(:prod, {__MODULE__, :prod_ok, [5, 10]})

      assert {:ok, 50, %{sum: 15, prod: 50}} == Chain.exec(chain)
    end

    test "async error with functions" do
      chain =
        Chain.new()
        |> Chain.put(:x, 5)
        |> Chain.put(:y, 10)
        |> Chain.run_async(:sum, fn _ -> {:error, :sum_reason} end)
        |> Chain.run_async(:prod, &({:ok, &1.x * &1.y}))

      assert {:error, {:sum, :sum_reason}, %{x: 5, y: 10, prod: 50}} == Chain.exec(chain)

      chain =
        Chain.new()
        |> Chain.put(:x, 5)
        |> Chain.put(:y, 10)
        |> Chain.run_async(:sum, &({:ok, &1.x + &1.y}))
        |> Chain.run_async(:prod, fn _ -> {:error, :prod_reason} end)

      assert {:error, {:prod, :prod_reason}, %{x: 5, y: 10, sum: 15}} == Chain.exec(chain)
    end

    test "async error with mfa" do
      chain =
        Chain.new()
        |> Chain.run_async(:sum, {__MODULE__, :sum_error, [5, 10]})
        |> Chain.run_async(:prod, {__MODULE__, :prod_ok, [5, 10]})

      assert {:error, {:sum, :sum_reason}, %{prod: 50}} == Chain.exec(chain)

      chain =
        Chain.new()
        |> Chain.run_async(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run_async(:prod, {__MODULE__, :prod_error, [5, 10]})

      assert {:error, {:prod, :prod_reason}, %{sum: 15}} == Chain.exec(chain)
    end

    test "final hooks with success" do
      chain =
        Chain.new()
        |> Chain.put(:parent, self())
        |> Chain.run(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run(:pow2, {__MODULE__, :pow2_ok, []})
        |> Chain.finally(fn result, effects ->
          send(effects.parent, {:result1, result})
          send(effects.parent, {:effects1, effects})
        end)
        |> Chain.finally(fn result, effects ->
          send(effects.parent, {:result2, result})
          send(effects.parent, {:effects2, effects})
        end)

      assert {:ok, 225, _} = Chain.exec(chain)

      assert_receive({:result1, {:ok, 225}})
      assert_receive({:effects1, %{sum: 15, pow2: 225}})
      assert_receive({:result2, {:ok, 225}})
      assert_receive({:effects2, %{sum: 15, pow2: 225}})
    end

    test "final hooks with error" do
      chain =
        Chain.new()
        |> Chain.put(:parent, self())
        |> Chain.run(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run(:pow2, {__MODULE__, :pow2_error, []})
        |> Chain.finally(fn result, effects ->
          send(effects.parent, {:result1, result})
          send(effects.parent, {:effects1, effects})
        end)
        |> Chain.finally(fn result, effects ->
          send(effects.parent, {:result2, result})
          send(effects.parent, {:effects2, effects})
        end)

      assert {:error, {:pow2, :pow2_reason}, _} = Chain.exec(chain)

      assert_receive({:result1, {:error, {:pow2, :pow2_reason}}})
      assert_receive({:effects1, %{sum: 15}})
      assert_receive({:result2, {:error, {:pow2, :pow2_reason}}})
      assert_receive({:effects2, %{sum: 15}})
    end

    test "final hooks with exception" do
      chain =
        Chain.new()
        |> Chain.put(:parent, self())
        |> Chain.run(:sum, {__MODULE__, :sum_ok, [5, 10]})
        |> Chain.run(:pow2, fn _ -> raise "error!" end)
        |> Chain.finally(fn result, effects ->
          send(effects.parent, {:result1, result})
          send(effects.parent, {:effects1, effects})
        end)
        |> Chain.finally(fn result, effects ->
          send(effects.parent, {:result2, result})
          send(effects.parent, {:effects2, effects})
        end)

      assert_raise(RuntimeError, fn -> Chain.exec(chain) end)

      assert_received({:result1, {:raise, {:pow2, _}}})
      assert_received({:effects1, %{sum: 15}})
      assert_received({:result2, {:raise, {:pow2, _}}})
      assert_received({:effects2, %{sum: 15}})
    end
  end
end
