# websocketpp vendored in external/websocketpp/, from the LocutusOfBorg fork's `boost` branch
# (67405e1a). SSC vendors the same 0.8.2 upstream, but against the pre-1.66 Boost.Asio API;
# this fork replaces io_service with io_context throughout. Vendoring it here is what lets
# xdyn build against modern Boost without modifying SSC.
#
# Included only for XDYN_NATIVE_BUILD: those replacements are unconditional, so this copy needs
# Boost >= 1.66, while the docker image keeps working against SSC's copy. Boost dropped
# io_service entirely by 1.89, so SSC's copy no longer compiles there at all.
SET(websocketpp_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/websocketpp)
