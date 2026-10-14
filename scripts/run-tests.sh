#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# Reconfigure build-hip with the test suite on, build every target, run ctest on GPU 0 (HIP_VISIBLE_DEVICES).
cd $MAYA_HOME/src
export ROCM_PATH=$ROCM_PATH HIP_PATH=$ROCM_PATH HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr
export PATH=$ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH LD_LIBRARY_PATH=$ROCM_PATH/lib
export HIP_VISIBLE_DEVICES=0
C=.venv/bin/cmake
$C -S . -B build-hip -DSTRATA_BUILD_TESTS=ON || { echo CONFIGURE_FAILED; exit 3; }
$C --build build-hip -j 4 -- -k 2>&1 | grep -v "Wunused\|nodiscard\|^ *[0-9]* |\|^ *|\|note: expanded" ; echo BUILD_EXIT=${PIPESTATUS[0]}
.venv/bin/ctest --test-dir build-hip --output-on-failure --timeout 180 -E '^(ple_parity|platform_memory_test)$'
echo CTEST_EXIT=$?
