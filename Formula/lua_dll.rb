class LuaDll < Formula
  desc "Powerful, lightweight programming language (dynamically linkable)"
  homepage "https://www.lua.org/"
  url "https://www.lua.org/ftp/lua-5.2.4.tar.gz"
  sha256 "b9e2e4aad6789b3b63a056d442f7b39f0ecfca3ae0f1fc0ae4e9614401b69f4b"
  revision 0

  conflicts_with "lua"

  bottle do
    cellar :any
    sha256 "5e52670b9b9c2554018545afcc13a08efde638aab521d39740c273992fc65922" => :el_capitan
    sha256 "3a1f5bfe0fd490c96e933b0726d327079b6a1cd6b9e881440173351ff9a349ad" => :yosemite
    sha256 "a84d3ebd9afa4a61b0120471e5a0dfcc670d294701a64edebd25fcc815fe76f8" => :mavericks
  end

  pour_bottle? do
    reason "The bottle needs to be installed into /usr/local."
    # DomT4: I'm pretty sure this can be fixed, so don't leave this in place forever.
    # https://github.com/Homebrew/homebrew/issues/44619
    satisfy { HOMEBREW_PREFIX.to_s == "/usr/local" }
  end

  fails_with :llvm do
    build 2326
    cause "Lua itself compiles with LLVM, but may fail when other software tries to link."
  end

  option :universal
  option "with-completion", "Enables advanced readline support"
  option "without-sigaction", "Revert to ANSI signal instead of improved POSIX sigaction"
  option "without-luarocks", "Don't build with Luarocks support embedded"

  depends_on "readline" unless OS.mac?

  # Be sure to build a dylib, or else runtime modules will pull in another static copy of liblua = crashy
  # See: https://github.com/Homebrew/homebrew/pull/5043
  patch :DATA if OS.mac?

  # On linux, patch the makefiles to also build a shared library.
  # http://lua-users.org/lists/lua-l/2006-10/msg00080.html
  if OS.linux?
    patch do
      url "https://gist.github.com/anonymous/ec85b1743c5cf799f43c/raw/489031798c95b0fa4a21f1a41aa57bd4cee2606f/lua-5.2.4-linux_build_shared.patch"
      sha256 "25a698129b3b87363b400269af7b6764e19756286e5a853266ba6d285b480e9a"
    end
  end

  # completion provided by advanced readline power patch
  # See http://lua-users.org/wiki/LuaPowerPatches
  if build.with? "completion"
    patch do
      url "http://luajit.org/patches/lua-5.2.0-advanced_readline.patch"
      sha256 "33d32d11fce4f85b88ce8f9bd54e6a6cbea376dfee3dbf8cdda3640e056bc29d"
    end
  end

  # sigaction provided by posix signalling power patch
  if build.with? "sigaction"
    patch do
      url "http://lua-users.org/files/wiki_insecure/power_patches/5.2/lua-5.2.3-sig_catch.patch"
      sha256 "f2e77f73791c08169573658caa3c97ba8b574c870a0a165972ddfbddb948c164"
    end
  end

  resource "luarocks" do
    url "https://keplerproject.github.io/luarocks/releases/luarocks-2.3.0.tar.gz"
    sha256 "68e38feeb66052e29ad1935a71b875194ed8b9c67c2223af5f4d4e3e2464ed97"
  end

  def install
    ENV.universal_binary if build.universal?

    # On linux, add -fPIC to CFLAGS to enable building as a shared library
    ENV["CFLAGS"] += " -fPIC" if OS.linux?

    # Subtitute formula prefix in `src/Makefile` for install name (dylib ID).
    inreplace "src/Makefile", "@LUA_PREFIX@", prefix if OS.mac?

    # Use our CC/CFLAGS to compile.
    inreplace "src/Makefile" do |s|
      s.remove_make_var! "CC"
      s.change_make_var! "CFLAGS", "#{ENV.cflags} -DLUA_COMPAT_ALL $(SYSCFLAGS) $(MYCFLAGS)"
      s.change_make_var! "MYLDFLAGS", ENV.ldflags
    end

    # Fix path in the config header
    inreplace "src/luaconf.h", "/usr/local", HOMEBREW_PREFIX

    # We ship our own pkg-config file as Lua no longer provide them upstream.
    arch = if OS.mac? then "macosx" elsif OS.linux? then "linux" else "posix" end
    system "make", arch, "INSTALL_TOP=#{prefix}", "INSTALL_MAN=#{man1}"
    system "make", "install", "INSTALL_TOP=#{prefix}", "INSTALL_MAN=#{man1}"
    (lib+"pkgconfig/lua.pc").write pc_file

    # Fix some software potentially hunting for different pc names.
    bin.install_symlink "lua" => "lua5.2"
    bin.install_symlink "lua" => "lua-5.2"
    bin.install_symlink "luac" => "luac5.2"
    bin.install_symlink "luac" => "luac-5.2"
    (include/"lua5.2").install_symlink include.children
    (lib/"pkgconfig").install_symlink "lua.pc" => "lua5.2.pc"
    (lib/"pkgconfig").install_symlink "lua.pc" => "lua-5.2.pc"

    # This resource must be handled after the main install, since there's a lua dep.
    # Keeping it in install rather than postinstall means we can bottle.
    if build.with? "luarocks"
      resource("luarocks").stage do
        ENV.prepend_path "PATH", bin

        system "./configure", "--prefix=#{libexec}", "--rocks-tree=#{HOMEBREW_PREFIX}",
                              "--sysconfdir=#{etc}/luarocks52", "--with-lua=#{prefix}",
                              "--lua-version=5.2", "--versioned-rocks-dir"
        system "make", "build"
        system "make", "install"

        (share+"lua/5.2/luarocks").install_symlink Dir["#{libexec}/share/lua/5.2/luarocks/*"]
        bin.install_symlink libexec/"bin/luarocks-5.2"
        bin.install_symlink libexec/"bin/luarocks-admin-5.2"
        bin.install_symlink libexec/"bin/luarocks"
        bin.install_symlink libexec/"bin/luarocks-admin"

        # This block ensures luarock exec scripts don't break across updates.
        inreplace libexec/"share/lua/5.2/luarocks/site_config.lua" do |s|
          s.gsub! libexec.to_s, opt_libexec
          s.gsub! include.to_s, "#{HOMEBREW_PREFIX}/include"
          s.gsub! lib.to_s, "#{HOMEBREW_PREFIX}/lib"
          s.gsub! bin.to_s, "#{HOMEBREW_PREFIX}/bin"
        end
      end
    end
  end

  def pc_file; <<-EOS.undent
    V= 5.2
    R= 5.2.4
    prefix=#{prefix}
    INSTALL_BIN= ${prefix}/bin
    INSTALL_INC= ${prefix}/include
    INSTALL_LIB= ${prefix}/lib
    INSTALL_MAN= ${prefix}/share/man/man1
    INSTALL_LMOD= ${prefix}/share/lua/${V}
    INSTALL_CMOD= ${prefix}/lib/lua/${V}
    exec_prefix=${prefix}
    libdir=${exec_prefix}/lib
    includedir=${prefix}/include

    Name: Lua
    Description: An Extensible Extension Language
    Version: 5.2.4
    Requires:
    Libs: -L${libdir} -llua -lm #{"-ldl" if OS.linux?}
    Cflags: -I${includedir}
    EOS
  end

  def caveats; <<-EOS.undent
    Please be aware due to the way Luarocks is designed any binaries installed
    via Luarocks-5.2 AND 5.1 will overwrite each other in #{HOMEBREW_PREFIX}/bin.

    This is, for now, unavoidable. If this is troublesome for you, you can build
    rocks with the `--tree=` command to a special, non-conflicting location and
    then add that to your `$PATH`.
    EOS
  end

  test do
    system "#{bin}/lua", "-e", "print ('Ducks are cool')"

    if File.exist?(bin/"luarocks-5.2")
      mkdir testpath/"luarocks"
      system bin/"luarocks-5.2", "install", "moonscript", "--tree=#{testpath}/luarocks"
      assert File.exist? testpath/"luarocks/bin/moon"
    end
  end
end

__END__
diff --git a/Makefile b/Makefile
index bd9515f..5940ba9 100644
--- a/Makefile
+++ b/Makefile
@@ -41,7 +41,7 @@ PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris
 # What to install.
 TO_BIN= lua luac
 TO_INC= lua.h luaconf.h lualib.h lauxlib.h lua.hpp
-TO_LIB= liblua.a
+TO_LIB= liblua.5.2.4.dylib
 TO_MAN= lua.1 luac.1

 # Lua version and release.
@@ -63,6 +63,8 @@ install: dummy
	cd src && $(INSTALL_DATA) $(TO_INC) $(INSTALL_INC)
	cd src && $(INSTALL_DATA) $(TO_LIB) $(INSTALL_LIB)
	cd doc && $(INSTALL_DATA) $(TO_MAN) $(INSTALL_MAN)
+	ln -s -f liblua.5.2.4.dylib $(INSTALL_LIB)/liblua.5.2.dylib
+	ln -s -f liblua.5.2.dylib $(INSTALL_LIB)/liblua.dylib

 uninstall:
	cd src && cd $(INSTALL_BIN) && $(RM) $(TO_BIN)
diff --git a/src/Makefile b/src/Makefile
index 8c9ee67..7f92407 100644
--- a/src/Makefile
+++ b/src/Makefile
@@ -28,7 +28,7 @@ MYOBJS=

 PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris

-LUA_A=	liblua.a
+LUA_A=	liblua.5.2.4.dylib
 CORE_O=	lapi.o lcode.o lctype.o ldebug.o ldo.o ldump.o lfunc.o lgc.o llex.o \
	lmem.o lobject.o lopcodes.o lparser.o lstate.o lstring.o ltable.o \
	ltm.o lundump.o lvm.o lzio.o
@@ -56,11 +56,12 @@ o:	$(ALL_O)
 a:	$(ALL_A)

 $(LUA_A): $(BASE_O)
-	$(AR) $@ $(BASE_O)
-	$(RANLIB) $@
+	$(CC) -dynamiclib -install_name @LUA_PREFIX@/lib/liblua.5.2.dylib \
+		-compatibility_version 5.2 -current_version 5.2.4 \
+		-o liblua.5.2.4.dylib $^

 $(LUA_T): $(LUA_O) $(LUA_A)
-	$(CC) -o $@ $(LDFLAGS) $(LUA_O) $(LUA_A) $(LIBS)
+	$(CC) -fno-common $(MYLDFLAGS) -o $@ $(LUA_O) $(LUA_A) -L. -llua.5.2.4 $(LIBS)

 $(LUAC_T): $(LUAC_O) $(LUA_A)
	$(CC) -o $@ $(LDFLAGS) $(LUAC_O) $(LUA_A) $(LIBS)
@@ -106,7 +107,7 @@ linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl -lreadline"

 macosx:
-	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLIBS="-lreadline" CC=cc
+	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX -fno-common" SYSLIBS="-lreadline" CC=cc

 mingw:
	$(MAKE) "LUA_A=lua52.dll" "LUA_T=lua.exe" \
