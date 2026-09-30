# Invictus "I've saved my files" page for Calamares (Venus, simple-mode.md
# 3.1): the last page before the install writes to the disk. Next stays off
# until the box is ticked.
#
# Built inside the Calamares tree: iso/aur-needed/calamares copies this
# folder to src/modules/diskcheck before configuring, so the package ships
# it like any other module. The block below also lets it build on its own
# against an installed Calamares (cmake -S installer/diskcheck).
if(NOT TARGET calamares)
    cmake_minimum_required(VERSION 3.16)
    project(invictus-diskcheck VERSION 1.0.0 LANGUAGES CXX)
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    find_package(Calamares 3.4 REQUIRED)
endif()

calamares_add_plugin(diskcheck
    TYPE viewmodule
    EXPORT_MACRO PLUGINDLLEXPORT_PRO
    SOURCES
        DiskCheckViewStep.cpp
    SHARED_LIB
)
