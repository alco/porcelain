defmodule PorcelainTest.GoonSignalTest do
  use ExUnit.Case

  alias Porcelain.Process, as: Proc
  alias Porcelain.Result

  @moduletag :goon

  setup_all do
    Porcelain.reinit(Porcelain.Driver.Goon)
  end

  test "kill signal" do
    proc = Porcelain.spawn("grep", ["foo", "--line-buffered"],
                                            in: :receive, out: {:send, self()})

    Proc.send_input(proc, "foo\nbar\n")
    :timer.sleep(100)
    assert Proc.alive?(proc)

    Proc.signal(proc, :kill)
    #Proc.send_input(proc, "")
    :timer.sleep(100)
    refute Proc.alive?(proc)

    proc_pid = proc.pid
    assert_receive {^proc_pid, :data, :out, "foo\n"}
    assert_receive {^proc_pid, :result, %Result{status: 255}}
    refute_receive _
  end

  @tag :posix
  test "term signal" do
    proc = Porcelain.spawn("grep", ["foo", "--line-buffered"],
                                            in: :receive, out: {:send, self()})

    Proc.send_input(proc, "foo\nbar\n")
    :timer.sleep(100)
    assert Proc.alive?(proc)

    Proc.signal(proc, 15)
    :timer.sleep(100)
    refute Proc.alive?(proc)

    proc_pid = proc.pid
    assert_receive {^proc_pid, :data, :out, "foo\n"}
    assert_receive {^proc_pid, :result, %Result{status: 255}}
    refute_receive _
  end
end
