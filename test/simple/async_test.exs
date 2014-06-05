defmodule PorcelainTest.AsyncTest do
  use ExUnit.Case

  alias Porcelain.Process
  alias Porcelain.Result

  test "spawn" do
    cmd = "head -n 3 | cut -b 1-4"

    proc = Porcelain.spawn(cmd, in: "multiple\nlines\nof input\n")
    assert %Process{port: _, out: :string, err: nil} = proc

    result = Process.await(proc)
    assert Process.closed?(proc)
    assert %Result{status: 0, out: "mult\nline\nof i\n", err: nil} = result
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

    proc = Porcelain.spawn(cmd, in: instream, out: :stream)
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
