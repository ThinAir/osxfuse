#!/bin/bash

# Copyright (c) 2011-2014 Benjamin Fleischer
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of osxfuse nor the names of its contributors may be used
#    to endorse or promote products derived from this software without specific
#    prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Homebrew
#
# ./build.sh -v 5 -t packagemanager -a build -- --library-prefix="${prefix}"
# ./build.sh -v 5 -t packagemanager -a install -- "${prefix}"

# MacPorts
#
# ./build.sh -v 5 --build-directory="${workpath}" -t packagemanager -a build --
#            [-a i386] [-a x86_64]
#            --framework-prefix="${prefix}"
#            --fsbundle-prefix="${prefix}"
#            --library-prefix="${prefix}"
# ./build.sh -v 5 -t packagemanager -a install -- "${destroot}"


declare -ra BUILD_TARGET_ACTIONS=("build" "clean" "install")

declare     PACKAGEMANAGER_FRAMEWORK_PREFIX=""
declare     PACKAGEMANAGER_FSBUNDLE_PREFIX=""
declare     PACKAGEMANAGER_LIBRARY_PREFIX="/usr/local"


function packagemanager_create_stage
{
    local stage_directory="${1}"
    common_assert "[[ -n `string_escape "${stage_directory}"` ]]"

    /bin/mkdir -p "${stage_directory}" \
                  "${stage_directory}/Library/Extensions/ThinAir/Filesystems" \
                  "${stage_directory}/Library/Extensions/ThinAir/Frameworks" \
                  "${stage_directory}/include" \
                  "${stage_directory}/lib" \
                  "${stage_directory}/lib/pkgconfig" 1>&3 2>&4
}

function packagemanager_build
{
    function packagemanager_build_getopt_handler
    {
        case "${1}" in
            --framework-prefix)
                PACKAGEMANAGER_FRAMEWORK_PREFIX="${2}"
                return 2
                ;;
            --fsbundle-prefix)
                PACKAGEMANAGER_FSBUNDLE_PREFIX="${2}"
                return 2
                ;;
            --library-prefix)
                PACKAGEMANAGER_LIBRARY_PREFIX="${2}"
                return 2
                ;;
        esac
    }

    build_target_getopt -p meta \
                     -s "a:,architecure:,framework-prefix:,fsbundle-prefix:,library-prefix:" \
                     -h packagemanager_build_getopt_handler \
                     -- \
                     "${@}"
    unset packagemanager_build_getopt_handler

    common_log_variable PACKAGEMANAGER_FSBUNDLE_PREFIX
    common_log_variable PACKAGEMANAGER_LIBRARY_PREFIX
    common_log_variable PACKAGEMANAGER_FRAMEWORK_PREFIX

    common_log "Clean target"
    build_target_invoke "${BUILD_TARGET_NAME}" clean
    common_die_on_error "Failed to clean target"

    common_log "Build target"

    local -a default_build_options=("${BUILD_TARGET_OPTION_ARCHITECTURES[@]/#/-a}"
                                    "-bENABLE_MACFUSE_MODE=0"
                                    "-mOSXFUSE_BUNDLE_PREFIX_LITERAL=${PACKAGEMANAGER_FSBUNDLE_PREFIX}")

    local -a library_build_options=("${BUILD_TARGET_OPTION_ARCHITECTURES[@]/#/-a}"
                                    "-mOSXFUSE_BUNDLE_PREFIX_LITERAL=${PACKAGEMANAGER_FSBUNDLE_PREFIX}")

    local stage_directory="${BUILD_TARGET_BUILD_DIRECTORY}"
    local debug_directory="${BUILD_TARGET_BUILD_DIRECTORY}/Debug"

    /bin/mkdir -p "${BUILD_TARGET_BUILD_DIRECTORY}" 1>&3 2>&4
    common_die_on_error "Failed to create build directory"

    packagemanager_create_stage "${stage_directory}"
    common_die_on_error "Failed to create stage"

    /bin/mkdir -p "${debug_directory}" 1>&3 2>&4
    common_die_on_error "Failed to create debug directory"

    # Build file system bundle

    build_target_invoke fsbundle build "${default_build_options[@]}"
    common_die_on_error "Failed to build file system bundle"

    build_target_invoke fsbundle install --debug="${debug_directory}" -- "${stage_directory}/Library/Extensions/ThinAir/Filesystems"
    common_die_on_error "Failed to install file system bundle"

    # Build library

    build_target_invoke library build "${library_build_options[@]}" --prefix="${PACKAGEMANAGER_LIBRARY_PREFIX}"
    common_die_on_error "Failed to build library"

    build_target_invoke library install --debug="${debug_directory}" --prefix="" -- "${stage_directory}"
    common_die_on_error "Failed to install library"

    /bin/ln -s "libosxfuse.2.dylib" "${stage_directory}/lib/libosxfuse_i64.2.dylib" && \
    /bin/ln -s "libosxfuse.dylib" "${stage_directory}/lib/libosxfuse_i64.dylib" && \
    /bin/ln -s "libosxfuse.la" "${stage_directory}/lib/libosxfuse_i64.la" && \
    /bin/ln -s "osxfuse.pc" "${stage_directory}/lib/pkgconfig/fuse.pc"
    common_die_on_error "Failed to create legacy library links"

    # Build framework

    build_target_invoke framework build "${default_build_options[@]}" \
                                        --library-prefix="${stage_directory}"
                                        -bINSTALL_PATH="${PACKAGEMANAGER_FRAMEWORK_PREFIX}/Library/Extensions/ThinAir/Frameworks" \
    common_die_on_error "Failed to build framework"

    build_target_invoke framework install --debug="${debug_directory}" -- "${stage_directory}/Library/Extensions/ThinAir/Frameworks"
    common_die_on_error "Failed to install framework"

    # Locate file system bundle

    local fsbundle_path=""
    fsbundle_path="`osxfuse_find "${stage_directory}/Library/Extensions/ThinAir/Filesystems"/*.fs`"
    common_die_on_error "Failed to locate file system bundle"

    # Move debug files into file system bundle

    /bin/mv "${debug_directory}" "${fsbundle_path}/Contents/"
    common_die_on_error "Failed to move debug files into file system bundle"
}

function packagemanager_install
{
    local -a arguments=()
    build_target_getopt -p install -o arguments -- "${@}"

    local target_directory="${arguments[0]}"
    if [[ ! -d "${target_directory}" ]]
    then
        common_die "Target directory '${target_directory}' does not exist"
    fi

    common_log "Install target"

    build_target_install "${BUILD_TARGET_BUILD_DIRECTORY}/" "${target_directory}"
    common_die_on_error "Failed to install target"
}
