defmodule PorcelainTest.GoonAsyncTest do
  use ExUnit.Case

  alias Porcelain.Process, as: Proc
  alias Porcelain.Result

  setup_all do
    :application.set_env(:porcelain, :driver, Porcelain.Driver.Goon)
  end

  test "spawn keep result" do
    proc = Porcelain.spawn("cut", ["-b", "1-4"],
                in: "multiple\nlines\nof input\n")
    assert %Proc{out: :string, err: nil} = proc

    :timer.sleep(100)

    assert Proc.alive?(proc)
    result = Proc.await(proc)
    refute Proc.alive?(proc)
    assert %Result{status: 0, out: "mult\nline\nof i\n", err: nil} = result
  end

  test "spawn discard result" do
    proc = Porcelain.spawn("cut", ["-b", "1-4"],
                in: "multiple\nlines\nof input\n", result: :discard)
    assert %Proc{out: :string, err: nil} = proc

    :timer.sleep(100)

    refute Proc.alive?(proc)
  end

  test "spawn and stop" do
    proc = Porcelain.spawn("grep", ["whatever"], in: :receive)

    :timer.sleep(100)
    assert Proc.alive?(proc)

    Proc.stop(proc)
    refute Proc.alive?(proc)

    assert Proc.await(proc) == {:error, :noproc}
  end

  test "spawn send input" do
    proc = Porcelain.spawn("grep", [":mark:", "--line-buffered"],
                           in: :receive, out: :stream)

    assert Enumerable.impl_for(proc.out) != nil

    pid = spawn(fn ->
      Proc.send_input(proc, "hello\n")
      Proc.send_input(proc, ":mark:\n")
      :timer.sleep(20)
      Proc.send_input(proc, "\n ignored \n")
      Proc.send_input(proc, ":mark:")
      Proc.send_input(proc, "\n ignored as well")
    end)

    :timer.sleep(100)
    assert Proc.alive?(proc)
    Proc.send_input(proc, "")

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
    proc = Porcelain.spawn("grep", [":mark:", "--line-buffered"],
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

    refute_receive {^proc_pid, :result, _}

    Proc.send_input(proc, "")
    assert_receive {^proc_pid, :result,
                      %Result{status: 0, out: {:send, ^self_pid}, err: nil}}
    refute Proc.alive?(proc)
  end

  test "spawn message passing no result" do
    self_pid = self()
    proc = Porcelain.spawn("grep", [":mark:", "--line-buffered"],
                       in: :receive, out: {:send, self_pid}, result: :discard)
    proc_pid = proc.pid

    Proc.send_input(proc, "-:mark:-")
    refute_receive _

    Proc.send_input(proc, "\n-")
    assert_receive {^proc_pid, :data, "-:mark:-\n"}
    Proc.send_input(proc, "")
    assert_receive {^proc_pid, :result, nil}
    refute Proc.alive?(proc)
  end

  #test "spawn streams" do
    #pid = self()

    #stream_fn = fn acc ->
      #send(pid, {:get_data, self()})
      #receive do
        #{^pid, :done}       -> nil
        #{^pid, data} -> {data, acc}
      #end
    #end
    #instream = Stream.unfold(nil, stream_fn)

    #proc = Porcelain.spawn("grep", [">end<", "-m", "2"],
                        #in: instream, out: :stream)
    #assert %Proc{err: nil} = proc
    #assert is_pid(proc.pid)
    #assert Enumerable.impl_for(proc.out) != nil

    #spawn(fn ->
      #send(pid, IO.iodata_to_binary(Enum.into(proc.out, [])))
      #send(pid, :ok)
    #end)

    #receive do
      #{:get_data, pid} -> send(pid, {self(), ["hello", [?\s, "wor"], "ld"]})
    #end
    #receive do
      #{:get_data, pid} -> send(pid, {self(), "|>end<|\n"})
    #end
    #receive do
      #{:get_data, pid} -> send(pid, {self(), "ignore me\n"})
    #end
    #receive do
      #{:get_data, pid} -> send(pid, {self(), [?>, ?e, [?n, [?d]], "<"]})
    #end

    #refute_receive :ok
    #assert Proc.alive?(proc)

    #receive do
      #{:get_data, pid} -> send(pid, {self(), "\n"})
    #end
    #assert_receive :ok
    #assert_receive "hello world|>end<|\n>end<\n"

    #refute Proc.alive?(proc)
  #end
end

#defmodule PorcelainAsyncRedirectsTest do
  #use ExUnit.Case, async: true

  #alias Porcelain, as: Porc

  #test "cat stdout to stderr /dev/null" do
    #{pid, _} = Porc.spawn("cat", in: "Hello world!", out: :err)
    #assert_receive {^pid, %Porc{status: 0, in: "Hello world!", out: nil, err: nil}}
  #end

  #test "cat stdout to stderr buffer" do
    #{pid, _} = Porc.spawn("cat", in: "Hello world!", out: :err, err: :buffer)
    #assert_receive {^pid, %Porc{status: 0, in: "Hello world!", out: nil, err: "Hello world!"}}
  #end

  #test "cat stderr to stdout /dev/null" do
    #{pid, _} = Porc.spawn("cat -goo", in: "Hello world!", err: :out)
    #assert_receive {^pid, %Porc{status: 1, in: "Hello world!", out: nil, err: nil}}
  #end

  #test "cat stderr to stdout buffer" do
    #{pid, _} = Porc.spawn("cat -goo", in: "Hello world!", err: :out, out: :buffer)
    #assert_receive {^pid, %Porc{status: 1, in: "Hello world!", out: <<_::binary>>, err: nil}}
  #end
#end
