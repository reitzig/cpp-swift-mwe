# cpp-swift-mwe

A minimal example that investigates how to build a Swift project that depends on a compiled, non-system C++ library.

Built from [@aciidb0mb3r](https://github.com/aciidb0mb3r)'s [blog post](http://ankit.im/swift/2016/05/21/creating-objc-cpp-packages-with-swift-package-manager/).

## Starting Point

Following the blog post closely, the initial project (commit 565752f6e27633b41b6c62c1ead700ba4e8d7d95) 
is structured as follows:
the Swift module depends on a C wrapper around a C++ module with sources.

`swift build` compiles all three modules; `.build/debug/swift` prints `5`.

## Goal

The ultimate goal is to use a C++ library -- let's call it C -- in Swift.

 * C is open source.
 * We can not expect C to be available on target systems.
 * We want to use a custom (minimal, platform specific) build of C.

Thus, as long as SwiftPM does not allow us to specify custom build instructions
for dependencies,
we have to supply the library as binary file, with headers to compile against.

Ideally, we want to receive a single build result that can be easily referenced
in other Swift projects, in particular such developed in XCode.

In case that is relevant, the library we want to build is to be used by
iOS apps.
