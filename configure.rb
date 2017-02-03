#!/usr/local/bin/ruby

require 'fileutils'

# # # # # # # # # # # # # # # # # # # #
#
#       Parameters
#
# # # # # # # # # # # # # # # # # # # #


# Define relevant system constants

SWIFTC = `which swiftc`.strip
CLANG  = `which clang`.strip
INSTNMTL = `which install_name_tool`.strip

FRAMEWORKS = "/Applications/Xcode8.2/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks" # TODO: determine dynamically
SYSROOT = "/Applications/Xcode8.2/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.12.sdk" # TODO: determine dynamically
CORES = 8

# Define relevant project constants

SOURCE_DIR = "Sources"
CPP_DIRS = ["cpplib"]
C_DIRS = ["cwrapper"]
SWIFT_DIRS = ["swift"]

BUILD_DIR = ".build"
DEPENDENCIES = [
    "Dependencies/libcpplib.dylib"
]

# Extract parameters

# TODO: configuration: debug vs release --> build folder; opt levels
# =>    Check release.yaml for other differences!
# TODO: take parameters from the outside!
# TODO: iOS targets!

CONFIG  = :debug
ARCH    = "x86_64"
BIT     = "64"
OSV     = "-mmacosx-version-min=10.10"
TARGET  = "x86_64-apple-macosx10.10"
OPT     = { c: ["-O0"], swift: ["-Onone"] } # release: [-O3] (?) and [-O, wmo]
# O2: most opts; O3: more opts, larger code; Oz like O2 but smaller code; O = O2


# # # # # # # # # # # # # # # # # # # #
#
#       Setup of helper functions
#
# # # # # # # # # # # # # # # # # # # #


def msg(msg, type = :info) # type one of :info, :warn, :error
    prefix = case type
    when :warn
        "Warning: "
    when :error
        "ERROR: "
    else
        ""
    end

    puts "#{prefix}#{msg}"
    Process.exit if error
end

def new_ending(sourcefile, type)
    #sourcefile.sub(/\.[^.]+$/, ".#{type.to_s}")
    "#{sourcefile}.#{type.to_s}"
end

def abspath(file)
    File.absolute_path(file)
end

def libname(dir)
    "lib#{dir}.dylib"
end

class MakeDef
    @name
    @value

    def initialize(name, value)
        @name = name
        @value = value
    end

    def to_s
        "#{@name} = #{@value}"
    end
end

class MakeRule
    @target
    @dependencies = []
    @commands = []

    def initialize(target, dependencies = [], commands = [])
        @target = target
        @dependencies = dependencies
        @commands = commands
    end

    def to_s
        deps = @dependencies.join(" ")
        cmds = @commands.map { |cmd|
            "\t" + cmd.join(" ")
        }.join("\n")

        "#{@target}: #{deps}\n#{cmds}"
    end
end


# # # # # # # # # # # # # # # # # # # #
#
#       Create Make targets
#
# # # # # # # # # # # # # # # # # # # #

targets = []

# # # # #
# Preamble
# # # # #


# # # # #
# Main targets
# # # # #

targets << MakeRule.new("build",
                        ["build-swift"])

targets << MakeRule.new("clean",
                        [],
                        [["rm", "-rf", "#{BUILD_DIR}"]])

# # # # #
# Prepare build folder
# # # # #

build_dirs = (C_DIRS + SWIFT_DIRS).map { |d| "#{d}.build" }.join(",")

targets << MakeRule.new("mkbuilddir",
                        [],
                        [["mkdir", "-p", "#{BUILD_DIR}/#{CONFIG.to_s}/{#{build_dirs}}"]])

targets << MakeRule.new("copydeps",
                        DEPENDENCIES + ["mkbuilddir"],
                        DEPENDENCIES.map { |d| [
                        ["cp", d, "#{BUILD_DIR}/#{CONFIG.to_s}/"]#,
                        # TODO necessary with libraries that were _really_ built exteranlly?
                        #       [INSTNMTL,
                        #         "-id @executable_path/libcpplib.dylib " +
                        #        "#{BUILD_DIR}/#{CONFIG.to_s}/#{File.basename(d)}"
                        #   ]
                        ]
                        }.flatten(1))

# # # # #
# Build targets for C wrapper libraries
# # # # #

# Order is irrelevant, so just recurse through the folders and
# build compile target for each file individually

targets << MakeRule.new("build-c",
                        C_DIRS.map { |d|
                            [libname(d), "#{d}.modulemap"]
                        }.flatten)

C_DIRS.each { |dir|
    # # # # #
    # Build C wrapper library
    # # # # #

    #targets << MakeDef.new("VPATH", "#{SOURCE_DIR}/#{dir}")

    # That didn't work. Since human readability is not important here,
    # going the one-target-per-file route.
    #
    #    targets << MakeRule.new(dir, ["#{BUILD_DIR}/#{dir}/%.o"], [[CLANG]]) # TODO link
    #targets << MakeRule.new("#{BUILD_DIR}/#{dir}/%.o",
    #                        ["%.c", "%.cpp"],
    #                        [[CLANG, "-F",FRAMEWORKS, "-fobjc-arc","-fmodules","-fmodule-name=#{dir}","-arch",ARCH,OSV,"-isysroot",SYSROOT,"-fmodules-cache-path=#{BUILD_DIR}/#{CONFIG.to_s}/ModuleCache","-g",OPT[:c],"-MD","-MT","dependencies","-MF","/Users/dhtp/Documents/cpp-swift-mwe/.build/debug/cpplib.build/empty.cpp.d","-c","/Users/dhtp/Documents/cpp-swift-mwe/Sources/cpplib/empty.cpp","-o","$@","-I","#{SOURCE_DIR}/#{dir}/include"]])

    o_files = []
    Dir["#{SOURCE_DIR}/#{dir}/**/*.{c,cpp}"].each { |src|
        s = File.basename(src) #.sub!(/^#{dir}/, "")
        o = new_ending("#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build/#{s}", :o)
        d = new_ending("#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build/#{s}", :d)

        o_files << o
        targets << MakeRule.new(o,
                                [src, "copydeps"],
                                [[CLANG, "-F", FRAMEWORKS,
                                         "-fobjc-arc",
                                         "-fmodules",
                                         "-fmodule-name=#{dir}",
                                         "-arch", ARCH,
                                         OSV,
                                         #"-m#{BIT}",
                                         "-isysroot", SYSROOT,
                                         "-fmodules-cache-path=" + abspath("#{BUILD_DIR}/#{CONFIG.to_s}/ModuleCache")] +
                                         CPP_DIRS.map { |cppd|
                                            ["-iquote", abspath("#{SOURCE_DIR}/#{cppd}/include")]
                                         }.flatten + [
                                         "-g"] +
                                         OPT[:c] + [
                                         "-MD",
                                         "-MT", "dependencies",
                                         "-MF", abspath(d),
                                         "-c", abspath(src),
                                         "-o", abspath(o),
                                         "-I", abspath("#{SOURCE_DIR}/#{dir}/include")#,
                                #        "-Wl", "-L" + abspath("#{BUILD_DIR}/#{CONFIG.to_s}"),
                                #        DEPENDENCIES.map { |d|
                                #           ["-Wl", "-l#{File.basename(d)}"]
                                #        }
                                ]])
    }

    # # # # #
    # Link C wrapper library
    # # # # #

    targets << MakeRule.new(libname(dir),
                            o_files + ["copydeps"],
                            [[CLANG,
                            "-F", FRAMEWORKS,
                            #"-arch", ARCH,
                            #OSV,
                            #"-m#{BIT}",
                            "-L" + abspath("#{BUILD_DIR}/#{CONFIG.to_s}")] +
                            CPP_DIRS.map { |d| "-l#{d}" } + #?
                            o_files + # TODO map to abspath(_) ?
                            ["-shared",
                            "-o", abspath("#{BUILD_DIR}/#{CONFIG.to_s}/") + "/#{libname(dir)}"
                            ]])

    # # # # #
    # Write modulemap for C wrapper library
    # # # # #
    # TODO is this the right way to do this?

    headers = Dir["#{SOURCE_DIR}/#{dir}/include/*.h"].map { |f| abspath(f) }
    mmap = abspath("#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build/module.modulemap")
    content =
%{module #{dir} {
    #{headers.map { |h| "umbrella header \\\"#{h}\\\""}.join("\n    ")}
    link \\\"#{dir}\\\"
    export *
}}
    # TODO what if there are more headers? Do we include all as "umbrella"?
    targets << MakeRule.new("#{dir}.modulemap",
                            [],
                            [["@echo \"\" > #{mmap}"]] +
                            content.split("\n").map { |line|
                                ["@echo \"#{line}\" >> #{mmap}"]
                            })
}

# # # # #
# Build targets for Swift files
# # # # #

targets << MakeRule.new("build-swift",
                        ["build-c"] + SWIFT_DIRS.map { |d| libname(d) })

SWIFT_DIRS.each { |dir|
    #targets << MakeDef.new("VPATH", "#{SOURCE_DIR}/#{dir}")

    # # # # #
    # Build Swift library
    # # # # #

    tmpdir = "#{BUILD_DIR}/#{CONFIG.to_s}/#{dir}.build"
    sources = Dir["#{SOURCE_DIR}/#{dir}/**/*.{swift}"]
    objects = sources.map { |src|
        s = File.basename(src) #.sub!(/^#{dir}/, "")
        new_ending("#{tmpdir}/#{s}", :o)
    }

    targets << MakeRule.new(libname(dir),
                            sources + ["copydeps"] + C_DIRS.map { |d| libname(d) },
                            [[SWIFTC,
                                "-I", abspath("#{BUILD_DIR}/#{CONFIG.to_s}"),
                                "-j#{CORES}",
                                "-D", "SWIFT_PACKAGE"] +
                                OPT[:swift] + [
                                "-g",
                                "-enable-testing",
                                "-F", FRAMEWORKS,
                                "-target", TARGET,
                                "-sdk", SYSROOT] +
                                C_DIRS.map { |cdir|
                                    ctmpdir = "#{BUILD_DIR}/#{CONFIG.to_s}/#{cdir}.build"
                                    ["-Xcc","-fmodule-map-file=#{abspath(ctmpdir)}/module.modulemap", # TODO
                                    "-I", abspath("#{SOURCE_DIR}/#{cdir}/include"),
                                ]}.flatten + [
                                "-module-cache-path", abspath("#{BUILD_DIR}/#{CONFIG.to_s}/ModuleCache")] +
                                sources.map { |s| abspath(s) }
                            ])

    # TODO
    #temps-path: "/Users/dhtp/Documents/cpp-swift-mwe/.build/debug/swift.build"
    #objects: ["/Users/dhtp/Documents/cpp-swift-mwe/.build/debug/swift.build/main.swift.o"]
    #is-library: false


    # # # # #
    # Link Swift library
    # # # # #
}

# # # # #
# Build Swift executable
# # # # #

# # # # #
# Create fat library
# # # # #

# TODO build fat lib (or executable?) using lipo

# # # # #
# Create Swift documentation
# # # # #

# TODO


# # # # # # # # # # # # # # # # # # # #
#
#       Write Makefile
#
# # # # # # # # # # # # # # # # # # # #

File.open("Makefile", "w") { |mf|
    mf.write("# Generated on #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} by #{ENV['USERNAME'] || ENV['USER']}\n\n")
    mf.write(targets.join("\n\n"))
}
