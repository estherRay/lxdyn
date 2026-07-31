"""Airy wave server with a seeded phase draw."""

import numpy as np
from xdyngrpc.waves.server import serve
from xdyngrpc.waves.server.airy import Airy

SEED = 0


class SeededAiry(Airy):
    """xdyngrpc's Airy model, with the ray phases drawn reproducibly.

    Airy.set_parameters draws its phases from the global numpy RNG, which nothing seeds.
    About one draw in five puts this scenario's cube into a state xdyn cannot integrate at
    dt = 1 s, and it aborts with "NaN detected in state U, at t = 1" -- so the suite failed
    roughly 20% of runs, at random, with no change on our side.

    Seeding is what the rest of the suite already does for the same reason: force's
    filtered_force.py reseeds per simulation, and waves_server/tests.py hands xdyn's own
    Airy model a "seed of the random data generator". The divergence itself is untouched,
    and is a property of a 1 s step on this cube rather than of the gRPC plumbing this
    scenario exercises.

    Reseeding per call, not once at import, because the server outlives a simulation: a
    second set_parameters would otherwise continue the first one's stream.
    """

    def set_parameters(self, parameters: str):
        np.random.seed(SEED)
        return super().set_parameters(parameters)


if __name__ == "__main__":
    serve(SeededAiry())
