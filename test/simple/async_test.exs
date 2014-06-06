defmodule PorcelainTest.SimpleAsyncTest do
  use ExUnit.Case

  alias Porcelain.Process
  alias Porcelain.Result

  test "spawn keep result" do
    cmd = "head -n 3 | cut -b 1-4"
    proc = Porcelain.spawn(cmd,
                in: "multiple\nlines\nof input\n", result: :keep)
    assert %Process{port: _, out: :string, err: nil, result: :keep} = proc

    :timer.sleep(100)

    refute Process.closed?(proc)
    result = Process.await(proc)
    assert Process.closed?(proc)
    assert %Result{status: 0, out: "mult\nline\nof i\n", err: nil} = result
  end

  test "spawn discard result" do
    cmd = "head -n 3 | cut -b 1-4"
    proc = Porcelain.spawn(cmd,
                in: "multiple\nlines\nof input\n", result: :discard)
    assert %Process{port: _, out: :string, err: nil, result: :discard} = proc

    :timer.sleep(100)

    assert Process.closed?(proc)
  end

  test "spawn send result" do
    cmd = "head -n 3 | cut -b 1-4"
    proc = Porcelain.spawn(cmd,
                in: "multiple\nlines\nof input\n", result: {:send, self()})
    assert %Process{port: _, out: :string, err: nil, result: {:send, _}} = proc

    ref = elem(proc.result, 1)
    assert is_reference(ref)

    :timer.sleep(100)

    assert Process.closed?(proc)
    assert_receive {^ref,
        %Result{status: 0,out: "mult\nline\nof i\n", err: nil}}
  end

  test "spawn send input" do
  end

  test "spawn streams" do
    cmd = {"grep", [">end<", "-m", "2"]}

    pid = self()

    stream_fn = fn acc ->
      send(pid, {:get_data, self()})
      receive do
        {^pid, :done}       -> nil
        {^pid, data} -> {data, acc}
      end
    end
    instream = Stream.unfold(nil, stream_fn)

    proc = Porcelain.spawn(cmd, in: instream, out: :stream, result: :discard)
    assert %Process{port: _, out: _, err: nil} = proc
    assert is_port(proc.port)
    assert Enumerable.impl_for(proc.out) != nil

    spawn(fn ->
      send(pid, IO.iodata_to_binary(Enum.into(proc.out, [])))
      send(pid, :ok)
    end)

    receive do
      {:get_data, pid} -> send(pid, {self(), ["hello", [?\s, "wor"], "ld"]})
    end
    receive do
      {:get_data, pid} -> send(pid, {self(), "|>end<|\n"})
    end
    receive do
      {:get_data, pid} -> send(pid, {self(), "ignore me\n"})
    end
    receive do
      {:get_data, pid} -> send(pid, {self(), [?>, ?e, [?n, [?d]], "<"]})
    end

    refute_receive :ok
    refute Process.closed?(proc)

    receive do
      {:get_data, pid} -> send(pid, {self(), "\n"})
    end
    assert_receive :ok
    assert_receive "hello world|>end<|\n>end<\n"

    assert Process.closed?(proc)
  end
end
