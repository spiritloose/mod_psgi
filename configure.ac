AC_INIT(mod_psgi, 0.0.1, jiro@cpan.org)

AC_ARG_WITH(apxs, AC_HELP_STRING([--with-apxs=NAME],
            [name of the apxs executable [[apxs]]]),
            [APXS="$with_apxs"])
if test -z "${APXS}"; then
    AC_PATH_PROGS(APXS, apxs2 apxs, no, [$PATH:/usr/sbin:/usr/local/apache2/bin])
fi
if test "$APXS" = no; then
    AC_MSG_ERROR([apxs not found. set apxs with --with-apxs.])
fi
AC_SUBST(APXS)

AC_ARG_WITH(apachectl, AC_HELP_STRING([--with-apctl=NAME],
            [name of the apachectl executable [[apachectl]]]),
            [APACHECTL="$with_apctl"])
if test -z "${APACHECTL}"; then
    AC_PATH_PROGS(APACHECTL, apache2ctl apachectl, no, [$PATH:/usr/sbin:/usr/local/apache2/bin])
fi
if test "$APACHECTL" = no; then
    AC_MSG_ERROR([apachectl not found. set apachectl with --with-apctl.])
fi
AC_SUBST(APACHECTL)

AC_ARG_WITH(perl, AC_HELP_STRING([--with-perl=NAME],
            [name of the perl executable [[perl]]]),
            [PERL="$with_perl"])
if test -z "${PERL}"; then
    AC_PATH_PROG(PERL, perl, no, [$PATH])
fi
if test "$PERL" = no; then
    AC_MSG_ERROR([perl not found set perl with --with-perl.])
fi
AC_SUBST(PERL)

AC_OUTPUT([Makefile t/Config.pm])

echo "
$PACKAGE_NAME $PACKAGE_VERSION configuration:
-----------------------
  apxs:              ${APXS}
  apachectl:         ${APACHECTL}
  perl:              ${PERL}

Now type 'make' to build $PACKAGE_NAME $PACKAGE_VERSION!
"
