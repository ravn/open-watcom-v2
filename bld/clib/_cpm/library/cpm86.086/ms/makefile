#pmake: build small 16bit cpm86 _cpm ix86 static os_dos cpu_i86
processor=086
model=ms
system=cpm86
linkage=static

!include ../../../../mklib.mif

# The CP/M-86 C startup (_cstart_). wlink's `system cpm86` block links it as an
# explicit `libfile cstartcpm.obj`, so it is emitted as a standalone object and
# is deliberately NOT archived into clibs.lib. Built via the mklib .asm rule.
all : cstartcpm.obj .SYMBOLIC
