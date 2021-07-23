using Test
using MPIClusterManagers
using Distributed

# Start workers via `mpiexec` that communicate among themselves via MPI;
# communicate with the workers via TCP
nprocs = parse(Int, ARGS[1])

mgr = MPIWorkerManager(nprocs)
addprocs(mgr; exeflags=`--project=$(Base.active_project())`)


@everywhere workers() begin
    using MPI
    MPI.Init()
end

refs = []
for w in workers()
    push!(refs, @spawnat w MPI.Comm_rank(MPI.COMM_WORLD))
end
ids = falses(nworkers())
for r in refs
    id = fetch(r)
    @test !ids[id+1]
    ids[id+1] = true
end
for id in ids
    @test id
end

s = @distributed (+) for i in 1:10
    i^2
end
@test s == 385
