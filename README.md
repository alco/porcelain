Porcelain
=========

Launch and communicate with external OS processes in Elixir without limitations
of Erlang ports. Porcelain builds on ports for easy integration, but provides
richer functionality and simple API for managing external processes.

Simply put, Porcelain removes the pain of dealing with ports and substitutes it
with happiness and peace of mind.


## Overview

Having some 20 odd options, the Erlang port API can be unwieldy and cumbersome
to use. Porcelain replaces it with a simpler approach and provides defaults for
the common cases.

User-level features include:

  * sane API

  * ability to launch external programs in a synchronous or asynchronous manner

  * multiple ways of passing input to the program and getting back its output
    (including working directly with files and Elixir streams)

  * (_to be implemented_) ability to send OS signals to external processes

  * (_to be implemented_) being able to work with programs that try to read the
    whole input until EOF before producing output

To find out more about the background on the library's design and possible
future extensions, please refer to the [wiki][].

  [wiki]: https://github.com/alco/porcelain/wiki


## Usage

Examples below show some of the common use cases. Refer to the API docs to
familiarize yourself the complete set of provided functions and options.


### Launching one-off programs

If you need to launch an external program, feed it some input and capture its
output and maybe also exit status, use `exec()` or `shell()`:

```elixir
alias Porcelain.Result

%Result{out: output, status: status} = Porcelain.shell("date")
IO.inspect status   #=> 0
IO.inspect output   #=> "Fri Jun  6 14:12:02 EEST 2014\n"

result = Porcelain.shell("date | cut -b 1-3")
IO.inspect result.out   #=> "Fri\n"

# Use exec() when you want launch a program directly without using a shell
File.write!("input.txt", "lines\nread\nfrom\nfile\n")
result = Porcelain.exec("sort", ["input.txt"])
IO.inspect result.out   #=> "file\nfrom\nlines\nread\n"
```


### Passing input and getting output

Porcelain gives you many options when it comes to interacting with external
processes. It is possible to feed input from a file or a stream, same for
output:

```elixir
File.write!("input.txt", """
  This file contains some patterns
  >like this<
  interspersed with other text
  ... >like this< the end.
  """)

Porcelain.exec("grep", [">like this<", "-m", "2"],
                    in: {:path, "input.txt"}, out: {:append, "output.txt"})
IO.inspect File.read!("output.txt")
#=> ">like this<\n... >like this< the end.\n"
```

Programs can be spawned asynchronously (using `spawn()` and `spawn_shell()`)
allowing for continuously exchaning data between Elixir and the external
process.

In the next example we will use streams for both input and output.

```elixir
alias Porcelain.Process, as: Proc

instream = SocketStream.new('example.com', 80)
opts = [in: instream, out: :stream]
proc = %Proc{out: outstream} = Porcelain.spawn("grep", ["div", "-m", "4"], opts)

Enum.into(outstream, IO.stream(:stdio, :line))
#     div {
#         div {
# <div>
# </div>

Proc.alive?(proc)   #=> false
```

The `SocketStream` module used above wraps a tcp socket in a stream. Its
implementation can be found in the `test/util/socket_stream.exs` file.

If you prefer to exchange messages with the external process, you can do that:

```elixir
alias Porcelain.Process, as: Proc
alias Porcelain.Result

proc = %Proc{pid: pid} =
  Porcelain.spawn_shell("grep ohai -m 2 --line-buffered",
                                in: :receive, out: {:send, self()})

Proc.send_input(proc, "ohai proc\n")
receive do
  {^pid, :data, data} -> IO.inspect data   #=> "ohai proc\n"
end

Proc.send_input(proc, "this won't match\n")
Proc.send_input(proc, "ohai")
Proc.send_input(proc, "\n")
receive do
  {^pid, :data, data} -> IO.inspect data   #=> "ohai\n"
end
receive do
  {^pid, :result, %Result{status: status}} -> IO.inspect status   #=> 0
end
```


## Going deeper

Take a look at the [reference docs][ref] for the full description of all
provided functions and supported options.

  [ref]: http://porcelain.readthedocs.org


## License

This software is licensed under [the MIT license](LICENSE).
