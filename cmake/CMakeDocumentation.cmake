# Add a target to generate API documentation with Doxygen
FIND_PACKAGE(Doxygen)

IF(DOXYGEN_FOUND)
    CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/docs/Doxyfile.in ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile @ONLY)
    CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/docs/DoxygenLayout.in ${CMAKE_CURRENT_BINARY_DIR}/DoxygenLayout.xml @ONLY)
    FILE(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/docs/doxygen")
    FILE(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/docs/doxygen/html")
    MESSAGE(STATUS "Adding doc_doxygen target")
    ADD_CUSTOM_TARGET(doc_doxygen
        ${DOXYGEN_EXECUTABLE} Doxyfile
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        COMMENT "Generating API documentation with Doxygen" VERBATIM
        )
ELSE()
    MESSAGE("Doxygen not found.")
ENDIF()
