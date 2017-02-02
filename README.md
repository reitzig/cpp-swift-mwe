# cpp-swift-mwe

A minimal example that investigates how to build a Swift project that depends on a compiled, non-system C++ library.

Built from [@aciidb0mb3r](https://github.com/aciidb0mb3r)'s [blog post](http://ankit.im/swift/2016/05/21/creating-objc-cpp-packages-with-swift-package-manager/).

## Starting Point

Following the blog post closely, the initial project (commit 565752f6e27633b41b6c62c1ead700ba4e8d7d95) is structured as follows:
the Swift module depends on a C wrapper around a C++ module with sources.

`swift build` compiles all three modules; `.build/debug/swift` prints `5`.
