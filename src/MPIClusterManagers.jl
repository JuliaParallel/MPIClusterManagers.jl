module MPIClusterManagers

export MPIManager, launch, manage, kill, procs, connect, mpiprocs, @mpi_do, TransportMode, MPI_ON_WORKERS, TCP_TRANSPORT_ALL, MPI_TRANSPORT_ALL, MPIWorkerManager

using Distributed, Serialization
import MPI

import Base: kill
import Sockets: connect, listenany, accept, IPv4, getsockname, getaddrinfo, wait_connected, IPAddr

include("workermanager.jl")
include("mpimanager.jl")
include("worker.jl")
include("mpido.jl")

end # module
