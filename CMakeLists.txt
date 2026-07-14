cmake_minimum_required(VERSION 3.5)

project(harbour-nami VERSION 0.8.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Set RPATH configuration BEFORE add_executable
set(CMAKE_SKIP_BUILD_RPATH FALSE)
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "\$ORIGIN/../lib64/harbour-nami:\$ORIGIN/../lib/harbour-nami")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH FALSE)

# Find Qt5
find_package(Qt5 REQUIRED COMPONENTS Core Gui Qml Quick Sql Concurrent)

# Translations (lrelease); optional so builds still work without linguist tools
find_package(Qt5LinguistTools QUIET)

# Find OpenCV
# For Sailfish OS: use bundled minimal OpenCV build
if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/opencv/lib")
    # Use bundled OpenCV (headers + libs)
    set(OpenCV_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/opencv/include/opencv4")
    set(OpenCV_LIB_DIR "${CMAKE_SOURCE_DIR}/3rdparty/opencv/lib")

    # Find the actual library files
    find_library(OpenCV_core_LIB opencv_core PATHS ${OpenCV_LIB_DIR} NO_DEFAULT_PATH)
    find_library(OpenCV_imgproc_LIB opencv_imgproc PATHS ${OpenCV_LIB_DIR} NO_DEFAULT_PATH)
    find_library(OpenCV_dnn_LIB opencv_dnn PATHS ${OpenCV_LIB_DIR} NO_DEFAULT_PATH)
    find_library(OpenCV_objdetect_LIB opencv_objdetect PATHS ${OpenCV_LIB_DIR} NO_DEFAULT_PATH)

    set(OpenCV_LIBS ${OpenCV_core_LIB} ${OpenCV_imgproc_LIB} ${OpenCV_dnn_LIB} ${OpenCV_objdetect_LIB})
    message(STATUS "Using bundled OpenCV minimal from 3rdparty/opencv")
    message(STATUS "OpenCV include: ${OpenCV_INCLUDE_DIRS}")
    message(STATUS "OpenCV libs: ${OpenCV_LIBS}")
else()
    # Fallback to system OpenCV (for local development)
    find_package(OpenCV REQUIRED COMPONENTS core imgproc dnn objdetect)
    message(STATUS "Using system OpenCV")
endif()

# Sources
set(SOURCES
    src/main.cpp
    src/logging.cpp
    src/facedetector.cpp
    src/facerecognizer.cpp
    src/facedatabase.cpp
    src/facepipeline.cpp
    src/faceimageprovider.cpp
    src/exifreader.cpp
)

# Headers
set(HEADERS
    src/logging.h
    src/facedetector.h
    src/facerecognizer.h
    src/facedatabase.h
    src/facepipeline.h
    src/faceimageprovider.h
    src/exifreader.h
)

# QML files are installed as a directory (see install(DIRECTORY qml ...))

# Create executable
add_executable(${PROJECT_NAME}
    ${SOURCES}
    ${HEADERS}
)

# App version shown in the About page (single source: project() above)
target_compile_definitions(${PROJECT_NAME} PRIVATE APP_VERSION="${PROJECT_VERSION}")

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${OpenCV_INCLUDE_DIRS}
)

# Link libraries
target_link_libraries(${PROJECT_NAME}
    Qt5::Core
    Qt5::Gui
    Qt5::Qml
    Qt5::Quick
    Qt5::Sql
    Qt5::Concurrent
    ${OpenCV_LIBS}
)

# Installation
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

install(DIRECTORY qml
    DESTINATION share/${PROJECT_NAME}
)

# Compile .ts -> .qm and install them
if(Qt5LinguistTools_FOUND)
    file(GLOB TS_FILES ${CMAKE_SOURCE_DIR}/translations/*.ts)
    qt5_add_translation(QM_FILES ${TS_FILES})
    add_custom_target(translations ALL DEPENDS ${QM_FILES})
    install(FILES ${QM_FILES}
        DESTINATION share/${PROJECT_NAME}/translations
    )
else()
    message(WARNING "Qt5LinguistTools not found - translations will not be built")
endif()

install(DIRECTORY python/models
    DESTINATION share/${PROJECT_NAME}
    FILES_MATCHING PATTERN "*.onnx"
)

install(FILES harbour-nami.desktop
    DESTINATION share/applications
)

# Install application icons
install(FILES icons/86x86/harbour-nami.png
    DESTINATION share/icons/hicolor/86x86/apps
)
install(FILES icons/108x108/harbour-nami.png
    DESTINATION share/icons/hicolor/108x108/apps
)
install(FILES icons/128x128/harbour-nami.png
    DESTINATION share/icons/hicolor/128x128/apps
)
install(FILES icons/172x172/harbour-nami.png
    DESTINATION share/icons/hicolor/172x172/apps
)

# Install bundled libraries to lib64/harbour-nami
# Use lib or lib64 depending on LIB_SUFFIX from spec file
if(LIB_SUFFIX)
    set(INSTALL_LIB_DIR "lib${LIB_SUFFIX}/harbour-nami")
else()
    set(INSTALL_LIB_DIR "lib/harbour-nami")
endif()

# Install OpenCV minimal libraries
if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/opencv/lib")
    file(GLOB OPENCV_LIBS_TO_INSTALL "${CMAKE_SOURCE_DIR}/3rdparty/opencv/lib/libopencv_*.so*")
    install(FILES ${OPENCV_LIBS_TO_INSTALL}
        DESTINATION "${INSTALL_LIB_DIR}"
    )
endif()

# Desktop file validation
find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_custom_target(validate_desktop ALL
        COMMAND ${DESKTOP_FILE_VALIDATE} ${CMAKE_SOURCE_DIR}/harbour-nami.desktop
    )
endif()
