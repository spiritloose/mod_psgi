mod_psgi.la: mod_psgi.slo
	$(SH_LINK) -rpath $(libexecdir) -module -avoid-version  mod_psgi.lo
DISTCLEAN_TARGETS = modules.mk
shared =  mod_psgi.la
