# MPIClusterManagers.jl

[![Travis Status](https://travis-ci.org/JuliaParallel/MPIClusterManagers.jl.svg?branch=master)](https://travis-ci.org/JuliaParallel/MPIClusterManagers.jl) [![Appveyor status](https://ci.appveyor.com/api/projects/status/xwpcsmp0fg582tf4/branch/master?svg=true)](https://ci.appveyor.com/project/simonbyrne/mpiclustermanagers-jl/branch/master)


## MPI and Julia parallel constructs together

In order for MPI calls to be made from a Julia cluster, it requires the use of
`MPIManager`, a cluster manager that will start the julia workers using `mpirun`

It has three modes of operation

- Only worker processes execute MPI code. The Julia master process executes outside of and
  is not part of the MPI cluster. Free bi-directional TCP/IP connectivity is required
  between all processes

- All processes (including Julia master) are part of both the MPI as well as Julia cluster.
  Free bi-directional TCP/IP connectivity is required between all processes.

- All processes are part of both the MPI as well as Julia cluster. MPI is used as the transport
  for julia messages. This is useful on environments which do not allow TCP/IP connectivity
  between worker processes Note: This capability works with Julia 1.0, 1.1 and 1.2 and releases
  after 1.4.2. It is broken for Julia 1.3, 1.4.0, and 1.4.1.

### MPIManager: only workers execute MPI code

An example is provided in `examples/juliacman.jl`.
The julia master process is NOT part of the MPI cluster. The main script should be
launched directly, `MPIManager` internally calls `mpirun` to launch julia/MPI workers.
All the workers started via `MPIManager` will be part of the MPI cluster.

```
MPIManager(;np=Sys.CPU_THREADS, mpi_cmd=false, launch_timeout=60.0)
```

If not specified, `mpi_cmd` defaults to `mpirun -np $np`
`stdout` from the launched workers is redirected back to the julia session calling `addprocs` via a TCP connection.
Thus the workers must be able to freely connect via TCP to the host session.
The following lines will be typically required on the julia master process to support both julia and MPI:

```julia
# to import MPIManager
using MPIClusterManagers

# need to also import Distributed to use addprocs()
using Distributed

# specify, number of mpi workers, launch cmd, etc.
manager=MPIManager(np=4)

# start mpi workers and add them as julia workers too.
addprocs(manager)
```

To execute code with MPI calls on all workers, use `@mpi_do`.

`@mpi_do manager expr` executes `expr` on all processes that are part of `manager`.

For example:
```julia
@mpi_do manager begin
  using MPI
  comm=MPI.COMM_WORLD
  println("Hello world, I am $(MPI.Comm_rank(comm)) of $(MPI.Comm_size(comm))")
end
```
executes on all MPI workers belonging to `manager` only

[`examples/juliacman.jl`](https://github.com/JuliaParallel/MPIClusterManagers.jl/blob/master/examples/juliacman.jl) is a simple example of calling MPI functions on all workers interspersed with Julia parallel methods.

This should be run _without_ `mpirun`:
```
julia juliacman.jl
```

A single instation of `MPIManager` can be used only once to launch MPI workers (via `addprocs`).
To create multiple sets of MPI clusters, use separate, distinct `MPIManager` objects.

`procs(manager::MPIManager)` returns a list of julia pids belonging to `manager`
`mpiprocs(manager::MPIManager)` returns a list of MPI ranks belonging to `manager`

Fields `j2mpi` and `mpi2j` of `MPIManager` are associative collections mapping julia pids to MPI ranks and vice-versa.

### MPIManager: TCP/IP transport - all processes execute MPI code

Useful on environments which do not allow TCP connections outside of the cluster

An example is in [`examples/cman-transport.jl`](https://github.com/JuliaParallel/MPIClusterManagers.jl/blob/master/examples/cman-transport.jl):
```
mpirun -np 5 julia cman-transport.jl TCP
```

This launches a total of 5 processes, mpi rank 0 is the julia pid 1. mpi rank 1 is julia pid 2 and so on.

The program must call `MPIClusterManagers.start_main_loop(TCP_TRANSPORT_ALL)` with argument `TCP_TRANSPORT_ALL`.
On mpi rank 0, it returns a `manager` which can be used with `@mpi_do`
On other processes (i.e., the workers) the function does not return


### MPIManager: MPI transport - all processes execute MPI code

`MPIClusterManagers.start_main_loop` must be called with option `MPI_TRANSPORT_ALL` to use MPI as transport.
```
mpirun -np 5 julia cman-transport.jl MPI
```
will run the example using MPI as transport.
