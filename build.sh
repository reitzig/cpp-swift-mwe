#!/bin/bash
pkg_root="$(cd "$(dirname "${0}")" && pwd)"

swift build -Xlinker -L"${pkg_root}"/Dependencies \
            -Xlinker -lcpplib
