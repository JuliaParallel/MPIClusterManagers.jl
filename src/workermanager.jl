


"""
    MPIWorkerManager([nprocs])

A [`ClusterManager`](https://docs.julialang.org/en/v1/stdlib/Distributed/#Distributed.ClusterManager)
using the MPI.jl launcher [`mpiexec`](https://juliaparallel.github.io/MPI.jl/stable/environment/#MPI.mpiexec).

The workers will all belong to an MPI session, and can communicate using MPI
operations. Note that unlike `MPIManager`, the MPI session will not be
initialized, so the workers will need to `MPI.Init()`.

The master process (pid 1) is _not_ part of the session, and will communicate
with the workers via TCP/IP.

# Usage

    using Distributed, MPIClusterManager

    mgr = MPIWorkerManager(4) # launch 4 MPI workers
    mgr = MPIWorkerManager() # launch the default number of MPI workers (determined by `mpiexec`)

    addprocs(mgr; kwoptions...)


The following `kwoptions` are supported:

 - `dir`: working directory on the workers.

 - `exename`: Julia executable on the workers.

 - `exeflags`: additional flags to pass to the Julia executable.

 - `topology`: how the workers connect to each other.

 - `enable_threaded_blas`: Whether the workers should use threaded BLAS.

 - `initmpi`: whether MPI should be initialized on the workers: the default is
   `false`, in which case it will try to determine each rank from an environment
   variable.

 - `launch_timeout`: the number of seconds to wait for workers to connect
   (default: `60`)

 - `mpiexec`: MPI launcher executable (default: use the launcher from MPI.jl)

 - `mpiflags`: additional flags  to pass to `mpiexec`

 - `master_tcp_interface`: Server interface to listen on. This allows direct
   connection from other hosts on same network as specified interface
   (otherwise, only connections from `localhost` are allowed).

"""
mutable struct MPIWorkerManager <: ClusterManager
    "number of MPI processes"
    nprocs::Union{Int, Nothing}
    "map `MPI.COMM_WORLD` rank to Julia pid"
    mpi2j::Dict{Int,Int}
    "map Julia pid to `MPI.COMM_WORLD` rank"
    j2mpi::Dict{Int,Int}
    "are the processes running?"
    launched::Bool
    "have the workers been initialized?"
    initialized::Bool
    "notify this when all workers registered"
    cond_initialized::Condition
    "redirected ios from workers"
    stdout_ios::Vector{IO}

    function MPIWorkerManager(nprocs = nothing)
        mgr = new(nprocs,
                  Dict{Int,Int}(),
                  Dict{Int,Int}(),
                  false,
                  false,
                  Condition(),
                  IO[]
                  )


        return mgr
    end

end

Distributed.default_addprocs_params(::MPIWorkerManager) =
    merge(Distributed.default_addprocs_params(),
          Dict{Symbol,Any}(
                :initmpi        => false,
                :launch_timeout => 60.0,
                :mpiexec        => nothing,
                :mpiflags       => ``,
                :master_tcp_interface => nothing,
          ))


# Launch a new worker, called from Base.addprocs
function Distributed.launch(mgr::MPIWorkerManager,
                            params::Dict,
                            instances::Array,
                            cond::Condition)

    mgr.launched && error("MPIWorkerManager already launched. Create a new instance to add more workers")

    launch_timeout = params[:launch_timeout]
    master_tcp_interface = params[:master_tcp_interface]

    if mgr.nprocs === nothing
        configs = WorkerConfig[]
    else
        configs =  Vector{WorkerConfig}(undef, mgr.nprocs)
    end

    # Set up listener
    if !isnothing(master_tcp_interface)
        # Listen on specified server interface
        # This allows direct connection from other hosts on same network as
        # specified interface.
        port, server =
            listenany(getaddrinfo(master_tcp_interface), 11000)
    else
        # Listen on default interface (localhost)
        # This precludes direct connection from other hosts.
        port, server = listenany(11000)
    end
    ip = getsockname(server)[1]


    connections = @async begin
        while isnothing(mgr.nprocs) || length(mgr.stdout_ios) < mgr.nprocs
            io = accept(server)
            config = WorkerConfig()
            config.io = io
            config.enable_threaded_blas = params[:enable_threaded_blas]

            # Add config to the correct slot so that MPI ranks and
            # Julia pids are in the same order
            rank = Serialization.deserialize(io)
            config.ident = (rank=rank,)
            nprocs = Serialization.deserialize(io)
            if mgr.nprocs === nothing
                if nprocs === nothing
                    error("Could not determine number of processes")
                end
                mgr.nprocs = nprocs
                resize!(configs, nprocs)
            end
            configs[rank+1] = config
            push!(mgr.stdout_ios, io)
        end
    end

    # Start the workers
    dir = params[:dir]
    exename = params[:exename]
    exeflags = params[:exeflags]
    mpiexec = params[:mpiexec]
    mpiflags = params[:mpiflags]
    if !isnothing(mgr.nprocs)
        mpiflags = `$mpiflags -n $(mgr.nprocs)`
    end

    cookie = Distributed.cluster_cookie()
    setup_cmds = "using Distributed; import MPIClusterManagers; MPIClusterManagers.setup_worker($(repr(string(ip))),$(port),$(repr(cookie)); initmpi=$(params[:initmpi]))"

    if isnothing(mpiexec)
        MPI.mpiexec() do mpiexec_cmd
            mpi_cmd = `$mpiexec_cmd $mpiflags $exename $exeflags -e $setup_cmds`
            open(detach(setenv(mpi_cmd, dir=dir)))
        end
    else
        mpi_cmd = `$mpiexec $mpiflags $exename $exeflags -e $setup_cmds`
        open(detach(setenv(mpi_cmd, dir=dir)))
    end
    mgr.launched = true

    # wait with timeout (https://github.com/JuliaLang/julia/issues/36217)
    timer = Timer(launch_timeout) do t
        schedule(connections, InterruptException(), error=true)
    end
    try
        wait(connections)
    catch e
        error("Could not connect to workers")
    finally
        close(timer)
    end

    # Append our configs and notify the caller
    append!(instances, configs)
    notify(cond)
end


function Distributed.manage(mgr::MPIWorkerManager, id::Integer, config::WorkerConfig, op::Symbol)
    if op == :register
        rank = config.ident.rank
        mgr.j2mpi[id] = rank
        mgr.mpi2j[rank] = id
        if length(mgr.j2mpi) == mgr.nprocs
            # All workers registered
            mgr.initialized = true
            notify(mgr.cond_initialized)
        end
    elseif op == :deregister
        # TODO: Sometimes -- very rarely -- Julia calls this `deregister`
        # function, and then outputs a warning such as """error in running
        # finalizer: ErrorException("no process with id 3 exists")""". These
        # warnings seem harmless; still, we should find out what is going wrong
        # here.
    elseif op == :interrupt
        # TODO: This should never happen if we rmprocs the workers properly
        @assert false
    elseif op == :finalize
        # This is called from within a finalizer after deregistering; do nothing
    else
        @assert false # Unsupported operation
    end
end
