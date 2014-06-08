defmodule PorcelainTest.BasicAsyncTest do
  use ExUnit.Case

  alias Porcelain.Process, as: Proc
  alias Porcelain.Result

  test "spawn keep result" do
    cmd = "head -n 3 | cut -b 1-4"
    proc = Porcelain.spawn_shell(cmd,
                in: "multiple\nlines\nof input\n")
    assert %Proc{out: :string, err: nil} = proc

    :timer.sleep(100)

    assert Proc.alive?(proc)
    result = Proc.await(proc)
    refute Proc.alive?(proc)
    assert %Result{status: 0, out: "mult\nline\nof i\n", err: nil} = result
  end

  test "spawn discard result" do
    cmd = "head -n 3 | cut -b 1-4"
    proc = Porcelain.spawn_shell(cmd,
                in: "multiple\nlines\nof input\n", result: :discard)
    assert %Proc{out: :string, err: nil} = proc

    :timer.sleep(100)

    refute Proc.alive?(proc)
  end

  test "spawn and stop" do
    cmd = "grep whatever"
    proc = Porcelain.spawn_shell(cmd, in: "whatever", result: :discard)

    :timer.sleep(100)
    assert Proc.alive?(proc)

    Proc.stop(proc)
    refute Proc.alive?(proc)

    assert Proc.await(proc) == {:error, :noproc}
  end

  test "spawn send input" do
    cmd = "grep ':mark:' -m 2 --line-buffered"
    proc = Porcelain.spawn_shell(cmd, in: :receive, out: :stream)

    assert Enumerable.impl_for(proc.out) != nil

    pid = spawn(fn ->
      Proc.send_input(proc, "hello\n")
      Proc.send_input(proc, ":mark:\n")
      :timer.sleep(10)
      Proc.send_input(proc, "\n ignored \n")
      Proc.send_input(proc, ":mark:")
      Proc.send_input(proc, "\n ignored as well")
    end)

    count = Enum.reduce(proc.out, 0, fn line, count ->
      assert line == ":mark:\n"
      count + 1
    end)
    assert count == 2
    refute Proc.alive?(proc)
    refute Process.alive?(pid)
  end

  test "spawn message passing" do
    self_pid = self()
    proc = Porcelain.spawn("grep", [":mark:", "-m", "2", "--line-buffered"],
                           in: :receive, out: {:send, self_pid})
    proc_pid = proc.pid

    Proc.send_input(proc, ":mark:")
    refute_receive _

    Proc.send_input(proc, "\n")
    assert_receive {^proc_pid, :data, ":mark:\n"}

    Proc.send_input(proc, "ignore me\n")
    refute_receive _

    Proc.send_input(proc, "123 :mark:\n")
    assert_receive {^proc_pid, :data, "123 :mark:\n"}
    assert_receive {^proc_pid, :result,
                      %Result{status: 0, out: {:send, ^self_pid}, err: nil}}
    refute Proc.alive?(proc)
  end

  test "spawn message passing no result" do
    self_pid = self()
    proc = Porcelain.spawn_shell("grep :mark: -m 1",
                       in: :receive, out: {:send, self_pid}, result: :discard)
    proc_pid = proc.pid

    Proc.send_input(proc, "-:mark:-")
    refute_receive _

    Proc.send_input(proc, "\n-")
    assert_receive {^proc_pid, :data, "-:mark:-\n"}
    assert_receive {^proc_pid, :result, nil}
    refute Proc.alive?(proc)
  end

  test "spawn streams" do
    pid = self()

    stream_fn = fn acc ->
      send(pid, {:get_data, self()})
      receive do
        {^pid, :done}       -> nil
        {^pid, data} -> {data, acc}
      end
    end
    instream = Stream.unfold(nil, stream_fn)

    proc = Porcelain.spawn("grep", [">end<", "-m", "2"],
                        in: instream, out: :stream)
    assert %Proc{err: nil} = proc
    assert is_pid(proc.pid)
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
    assert Proc.alive?(proc)

    receive do
      {:get_data, pid} -> send(pid, {self(), "\n"})
    end
    assert_receive :ok
    assert_receive "hello world|>end<|\n>end<\n"

    refute Proc.alive?(proc)
  end
end
