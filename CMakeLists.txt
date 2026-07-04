cmake_minimum_required(VERSION 3.5)

project(harbour-nami VERSION 0.4.0 LANGUAGES CXX)

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

# ONNX Runtime - manual for now (will be bundled)
set(ONNXRUNTIME_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/3rdparty/onnxruntime/include")
set(ONNXRUNTIME_LIB_DIR "${CMAKE_SOURCE_DIR}/3rdparty/onnxruntime/lib")

# Find ONNX Runtime library
find_library(ONNXRUNTIME_LIB onnxruntime PATHS ${ONNXRUNTIME_LIB_DIR} NO_DEFAULT_PATH)
if(NOT ONNXRUNTIME_LIB)
    message(FATAL_ERROR "ONNX Runtime library not found in ${ONNXRUNTIME_LIB_DIR}")
endif()
message(STATUS "ONNX Runtime lib: ${ONNXRUNTIME_LIB}")

# Sources
set(SOURCES
    src/main.cpp
    src/facedetector.cpp
    src/facerecognizer.cpp
    src/facedatabase.cpp
    src/facepipeline.cpp
)

# Headers
set(HEADERS
    src/facedetector.h
    src/facerecognizer.h
    src/facedatabase.h
    src/facepipeline.h
)

# QML files
set(QML_FILES
    qml/harbour-nami.qml
    qml/pages/MainPage.qml
    qml/pages/PhotoGridPage.qml
    qml/pages/PersonDetailPage.qml
    qml/pages/PhotoViewerPage.qml
    qml/pages/UnknownFacesPage.qml
    qml/pages/IdentifyFacesPage.qml
    qml/pages/SettingsPage.qml
    qml/pages/ScanningPage.qml
    qml/pages/ScanResultsPage.qml
    qml/pages/EventsPage.qml
    qml/pages/MemoriesPage.qml
    qml/dialogs/IdentifyFaceDialog.qml
    qml/dialogs/SelectPersonDialog.qml
    qml/components/FaceRecognitionManager.qml
    qml/components/PhotoThumbnail.qml
    qml/components/FaceThumbnail.qml
    qml/cover/CoverPage.qml
)

# Create executable
add_executable(${PROJECT_NAME}
    ${SOURCES}
    ${HEADERS}
)

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${ONNXRUNTIME_INCLUDE_DIR}
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
    ${ONNXRUNTIME_LIB}
)

# Installation
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

install(DIRECTORY qml
    DESTINATION share/${PROJECT_NAME}
)

install(DIRECTORY translations
    DESTINATION share/${PROJECT_NAME}
    FILES_MATCHING PATTERN "*.qm"
)

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

# Install ONNX Runtime library
if(EXISTS "${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so.1.16.3")
    install(FILES "${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so.1.16.3"
        DESTINATION "${INSTALL_LIB_DIR}"
    )
    # Create symlink
    install(CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink \
        libonnxruntime.so.1.16.3 \
        \$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/${INSTALL_LIB_DIR}/libonnxruntime.so)")
elseif(EXISTS "${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so")
    # Fallback if versioned lib doesn't exist
    install(FILES "${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so"
        DESTINATION "${INSTALL_LIB_DIR}"
        RENAME libonnxruntime.so.1.16.3
    )
endif()

# Desktop file validation
find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_custom_target(validate_desktop ALL
        COMMAND ${DESKTOP_FILE_VALIDATE} ${CMAKE_SOURCE_DIR}/harbour-nami.desktop
    )
endif()
