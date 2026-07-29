CMAKE_MINIMUM_REQUIRED(VERSION 2.8.8)
PROJECT(observers_and_api)

# #embed is C++26; both compilers take it earlier as an extension, and this project
# builds with -pedantic-errors, which promotes that to an error. Scoped to the one file
# that needs it -- build.zig passes clang the same exemption as -Wno-c23-extensions.
SET_SOURCE_FILES_PROPERTIES(demo_scripts.cpp PROPERTIES COMPILE_OPTIONS "-Wno-c++26-extensions")

SET(SRC
    ConfBuilder.cpp
    demo_scripts.cpp
    CoSimulationObserver.cpp
    CsvObserver.cpp
    DictObserver.cpp
    EverythingObserver.cpp
    gRPCProtoBufServer.cpp
    Hdf5Observer.cpp
    Hdf5WaveObserverBuilder.cpp
    Hdf5WaveObserver.cpp
    Hdf5WaveSpectrumObserver.cpp
    JsonObserver.cpp
    JSONSerializer.cpp
    ListOfObservers.cpp
    MapObserver.cpp
    SimObserver.cpp
    SimServerInputs.cpp
    SimulationServerObserver.cpp
    simulator_api.cpp
    TsvObserver.cpp
    WebSocketObserver.cpp
    XdynForCS.cpp
    XdynForME.cpp
    )

INCLUDE_DIRECTORIES(${ssc_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(${CMAKE_BINARY_DIR})
INCLUDE_DIRECTORIES(SYSTEM ${Boost_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(SYSTEM ${eigen_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(SYSTEM ${eigen_hdf5_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(SYSTEM ${GRPC_INCLUDE_DIR})
INCLUDE_DIRECTORIES(SYSTEM ${HDF5_INCLUDE_DIR})
INCLUDE_DIRECTORIES(SYSTEM ${YAML_CPP_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(SYSTEM ${THIRDPARTY_CODE_INCLUDE_DIR})

ADD_LIBRARY(${PROJECT_NAME} OBJECT ${SRC})

ADD_SUBDIRECTORY(unit_tests)
