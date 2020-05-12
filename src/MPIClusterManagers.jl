module MPIClusterManagers

export MPIManager, launch, manage, kill, procs, connect, mpiprocs, @mpi_do, TransportMode, MPI_ON_WORKERS, TCP_TRANSPORT_ALL, MPI_TRANSPORT_ALL

using Distributed, Serialization
import MPI

include("mpimanager.jl")

end # module
