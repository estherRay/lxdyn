# websocketpp vendored in code/websocketpp/, from the LocutusOfBorg fork's `boost` branch
# (67405e1a). SSC vendors the same 0.8.2 upstream, but against the pre-1.66 Boost.Asio API;
# this fork replaces io_service with io_context throughout. Vendoring it here is what lets
# xdyn build against modern Boost without modifying SSC.
#
# NOT included yet: those replacements are unconditional, so this copy requires Boost >= 1.66
# and the docker image's Boost predates it. The switch happens with the Nix devShell.
SET(websocketpp_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/websocketpp)
